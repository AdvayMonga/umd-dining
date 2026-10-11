"""Dining hall hours from UMD Dining's own schedule.

dining.umd.edu/hours/open-now renders hours client-side from a public Google
Sheet (gviz JSON). Row 0 holds the dates ("venue", "1/1/2026", ...); each later
row is one "<Hall> | <Meal>" with cells like "7am-10:30am", "Closed" or blank.

Parsed into {hall_id: {"YYYY-MM-DD": [{"meal", "open", "close"}]}}. A date with
an empty list is a known closed day; a missing date means the sheet doesn't say
(blank/TBD), so clients should fall back to their own default schedule.
"""
import json
import re
import threading
import time
from datetime import date, datetime, timezone

import requests

SHEET_URL = ('https://docs.google.com/spreadsheets/d/1vdWskGO2-aJfKLSW8-3zMaj_nx4SBJHF3OvMEy4-ZNo'
             '/gviz/tq?gid=479022338')
SOURCE_PAGE = 'https://dining.umd.edu/hours/open-now'

# Sheet venue name -> app hall id
HALL_IDS = {
    'south campus': '16',
    'yahentamitsi': '19',
    '251 north': '51',
}

REFRESH_SECONDS = 3600
RETRY_SECONDS = 300  # after a failed refresh, keep serving the last copy and retry sooner

CLOSED = 'closed'

_TIME_RE = re.compile(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$')
_DATE_RE = re.compile(r'^(\d{1,2})/(\d{1,2})/(\d{4})$')
_GVIZ_DATE_RE = re.compile(r'^Date\((\d{4}),(\d{1,2}),(\d{1,2})')


class HoursUnavailable(Exception):
    """No schedule could be fetched and there's no cached copy to serve."""


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def _parse_time(text: str):
    """'7am' / '10:30 pm' / 'noon' -> (hour, minute, meridiem or None). None if unparseable."""
    t = text.strip().lower().replace('.', '').replace(' ', '')
    if t == 'noon':
        return 12, 0, 'pm'
    if t == 'midnight':
        return 12, 0, 'am'
    m = _TIME_RE.match(t)
    if not m:
        return None
    hour, minute = int(m.group(1)), int(m.group(2) or 0)
    if not 1 <= hour <= 12 or minute > 59:
        return None
    return hour, minute, m.group(3)


def _to_minutes(hour: int, minute: int, meridiem: str) -> int:
    return (hour % 12 + (12 if meridiem == 'pm' else 0)) * 60 + minute


def parse_window(text):
    """One sheet cell -> (open_min, close_min), CLOSED, or None (unknown: blank, TBD, garbage)."""
    if text is None:
        return None
    t = str(text).strip().lower()
    if not t:
        return None
    if t.startswith('closed'):
        return CLOSED
    t = t.replace('\u2013', '-').replace('\u2014', '-').replace(' to ', '-')
    parts = t.split('-')
    if len(parts) != 2:
        return None
    start, end = _parse_time(parts[0]), _parse_time(parts[1])
    # The close time must say am/pm; "7-10:30" is too ambiguous to guess at
    if start is None or end is None or end[2] is None:
        return None
    close = _to_minutes(*end)
    if close == 0:
        close = 24 * 60  # "...-12am" / "...-midnight"
    opening = _to_minutes(start[0], start[1], start[2] or end[2])
    if start[2] is None and opening >= close:
        opening = _to_minutes(start[0], start[1], 'am')  # "10-2pm" means 10am
    if opening >= close:
        return None
    return opening, close


def _cell_value(cell):
    if not cell:
        return None
    v = cell.get('v')
    return v if v is not None else cell.get('f')


def _parse_header_date(value):
    if value is None:
        return None
    s = str(value).strip()
    m = _DATE_RE.match(s)
    if m:
        month, day, year = map(int, m.groups())
    else:
        m = _GVIZ_DATE_RE.match(s)  # typed date column: months are 0-based
        if not m:
            return None
        year, month, day = int(m.group(1)), int(m.group(2)) + 1, int(m.group(3))
    try:
        return date(year, month, day)
    except ValueError:
        return None


def _fmt(minutes: int) -> str:
    return f'{minutes // 60:02d}:{minutes % 60:02d}'


def unwrap_gviz(text: str) -> dict:
    """Strip the google.visualization.Query.setResponse( ... ); wrapper."""
    start, end = text.find('('), text.rfind(')')
    if start == -1 or end <= start:
        raise ValueError('not a gviz response')
    return json.loads(text[start + 1:end])


def parse_sheet(text: str) -> dict:
    """gviz text -> {hall_id: {date: [windows]}} for every date the sheet knows about."""
    payload = unwrap_gviz(text)
    rows = (payload.get('table') or {}).get('rows') or []
    if not rows:
        raise ValueError('sheet has no rows')
    header = [_parse_header_date(_cell_value(c)) for c in rows[0].get('c') or []]

    # {hall_id: {date: [(open, close, meal)], or None once any meal cell that day is unknown}}
    days: dict = {}
    for row in rows[1:]:
        cells = row.get('c') or []
        label = _cell_value(cells[0]) if cells else None
        if not isinstance(label, str) or '|' not in label:
            continue
        venue, meal = (p.strip() for p in label.split('|', 1))
        hall_id = HALL_IDS.get(venue.lower())
        if not hall_id or not meal:
            continue
        by_date = days.setdefault(hall_id, {})
        for i, d in enumerate(header):
            if d is None:
                continue
            key = d.isoformat()
            window = parse_window(_cell_value(cells[i]) if i < len(cells) else None)
            if window is None:
                # A day is only known when every meal is: "Closed" breakfast + TBD dinner isn't closed
                by_date[key] = None
                continue
            day = by_date.setdefault(key, [])
            if day is not None and window != CLOSED:
                day.append((window[0], window[1], meal))

    if not days:
        raise ValueError('sheet has no recognizable hall rows')
    return {
        hall_id: {
            d: [{'meal': meal, 'open': _fmt(o), 'close': _fmt(c)} for o, c, meal in sorted(windows)]
            for d, windows in by_date.items() if windows is not None
        }
        for hall_id, by_date in days.items()
    }


# ---------------------------------------------------------------------------
# Fetch + cache
# ---------------------------------------------------------------------------

def fetch_sheet_text() -> str:
    resp = requests.get(SHEET_URL, timeout=10)
    resp.raise_for_status()
    return resp.text


class HoursCache:
    """In-process cache: refresh at most hourly, keep the last good copy on failure."""

    def __init__(self, fetcher=fetch_sheet_text, clock=time.time):
        self._fetcher = fetcher
        self._clock = clock
        self._lock = threading.Lock()
        self._copy = None  # (schedule, fetched_at), swapped as a unit so readers never see a mix
        self._expires = 0.0

    def get(self):
        """Returns (schedule, fetched_at). Blocking — call off the event loop."""
        if self._clock() < self._expires:
            return self._serve()
        # Stale-while-revalidate: if another request is already refreshing, don't queue behind it
        if not self._lock.acquire(blocking=self._copy is None):
            return self._copy
        try:
            if self._clock() < self._expires:  # another request refreshed (or failed) while we waited
                return self._serve()
            try:
                schedule = parse_sheet(self._fetcher())
            except Exception as e:
                # Back off either way, so a dead sheet doesn't cost every request a 10s timeout
                self._expires = self._clock() + RETRY_SECONDS
                if self._copy is None:
                    raise HoursUnavailable(str(e))
                print(f"Hours refresh failed, serving copy from {self._copy[1]}: {e}")
                return self._copy
            fetched_at = datetime.fromtimestamp(self._clock(), timezone.utc).isoformat(timespec='seconds')
            self._copy = (schedule, fetched_at)
            self._expires = self._clock() + REFRESH_SECONDS
            return self._copy
        finally:
            self._lock.release()

    def _serve(self):
        # Within the expiry window: the good copy, or nothing during a failure backoff
        if self._copy is None:
            raise HoursUnavailable('hours fetch failed recently; retrying soon')
        return self._copy


cache = HoursCache()


def window_range(schedule: dict, dates: list) -> dict:
    """Slice the schedule to the given ISO dates; dates the sheet doesn't cover are omitted."""
    return {
        hall_id: {d: by_date[d] for d in dates if d in by_date}
        for hall_id, by_date in schedule.items()
    }
