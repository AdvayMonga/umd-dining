"""Hall hours: gviz parsing, the hourly cache, and /api/hours."""
import json
import threading

import pytest
from fastapi import HTTPException

import hours
import routes


def gviz(rows, labels=()):
    """Wrap rows of plain values the way Google's gviz endpoint does."""
    table = {"cols": [{"label": label} for label in labels],
             "rows": [{"c": [None if v is None else {"v": v} for v in r]} for r in rows]}
    body = json.dumps({"version": "0.6", "status": "ok", "table": table})
    return f"/*O_o*/\ngoogle.visualization.Query.setResponse({body});"


# Fall break 2026: Yahentamitsi closed Sat 10/10, dinner only Tue 10/13
SHEET = gviz([
    ["venue", "10/10/2026", "10/13/2026", "10/14/2026", "1/25/2027"],
    ["Yahentamitsi | Breakfast", "Closed ", "Closed ", "7am-10:30am", "TBD"],
    ["Yahentamitsi | Lunch", "Closed ", "Closed", "10:30am-4pm", "TBD"],
    ["Yahentamitsi | Dinner", "Closed ", "4pm-9pm", "4pm-9pm", None],
    ["251 North | Breakfast", "8am-10:30am", "8am-10:30am", "8am-10:30am", "TBD"],
    ["251 North | Dinner", "4pm-9pm", "4pm-10pm", "4pm-10pm", "TBD"],
    ["Mystery Hall | Lunch", "11am-2pm", "11am-2pm", "11am-2pm", "11am-2pm"],
    [None, None, None, None, None],
])


@pytest.mark.parametrize("text, expected", [
    ("7am-10:30am", (420, 630)),
    ("4pm-9pm", (960, 1260)),
    ("12pm-1:30pm", (720, 810)),
    ("Noon-2pm", (720, 840)),
    ("10-2pm", (600, 840)),            # start without am/pm borrows, then flips to am
    ("11 a.m. – 1:30 p.m.", (660, 810)),
    ("4pm-12am", (960, 1440)),         # closing at midnight is end of day, not minute 0
    ("Closed", hours.CLOSED),
    ("Closed ", hours.CLOSED),
    ("CLOSED for break", hours.CLOSED),
])
def test_parse_window(text, expected):
    assert hours.parse_window(text) == expected


@pytest.mark.parametrize("text", [None, "", "   ", "TBD", "—", "12pm", "7-9", "9pm-7am", "25am-3pm"])
def test_unknown_cells_are_not_guessed(text):
    assert hours.parse_window(text) is None


def test_parse_sheet_closed_dinner_only_and_unknown_days():
    s = hours.parse_sheet(SHEET)
    assert set(s) == {"19", "51"}                     # unknown venues and blank rows skipped
    assert s["19"]["2026-10-10"] == []                # closed all day
    assert s["19"]["2026-10-13"] == [{"meal": "Dinner", "open": "16:00", "close": "21:00"}]
    assert [w["meal"] for w in s["19"]["2026-10-14"]] == ["Breakfast", "Lunch", "Dinner"]
    assert "2027-01-25" not in s["19"]                # all TBD/blank -> unknown, not closed
    assert s["51"]["2026-10-13"][-1] == {"meal": "Dinner", "open": "16:00", "close": "22:00"}


def test_one_unknown_meal_makes_the_whole_day_unknown():
    sheet = gviz([
        ["venue", "10/10/2026", "10/11/2026", "10/12/2026", "10/13/2026"],
        ["Yahentamitsi | Breakfast", "Closed", "Closed", "Closed", "Closed"],
        ["Yahentamitsi | Lunch", "TBD", "Closed", "", "Closed"],
        ["Yahentamitsi | Dinner", "4pm-9pm", "Closed", "Closed"],    # short row: 10/13 has no cell
    ])
    s = hours.parse_sheet(sheet)
    assert s["19"] == {"2026-10-11": []}   # only the day every meal cell speaks for


def test_parse_sheet_handles_typed_date_headers():
    sheet = gviz([["venue", "Date(2026,9,10)"], ["Yahentamitsi | Dinner", "4pm-9pm"]])
    assert hours.parse_sheet(sheet) == {"19": {"2026-10-10": [{"meal": "Dinner", "open": "16:00", "close": "21:00"}]}}


def test_parse_sheet_falls_back_to_column_labels_for_dates():
    sheet = gviz([["Yahentamitsi | Dinner", "4pm-9pm"]], labels=["venue", "10/10/2026"])
    assert hours.parse_sheet(sheet) == {"19": {"2026-10-10": [{"meal": "Dinner", "open": "16:00", "close": "21:00"}]}}


@pytest.mark.parametrize("text", [
    "<html>sign in</html>",
    gviz([]),
    gviz([["venue", "1/1/2026"], ["Foo | Lunch", "1pm-2pm"]]),
    gviz([["venue", "1/1/2026"], ["Yahentamitsi | Lunch", ""], ["251 North | Lunch", "TBD"]]),   # blanked
    gviz([["venue", "someday"], ["Yahentamitsi | Lunch", "1pm-2pm"]], labels=["", "A"]),         # no dates
])
def test_parse_sheet_rejects_unusable_responses(text):
    with pytest.raises(ValueError):
        hours.parse_sheet(text)


def test_window_range_omits_dates_outside_the_sheet():
    s = hours.parse_sheet(SHEET)
    out = hours.window_range(s, ["2026-10-13", "2030-01-01"])
    assert out["19"] == {"2026-10-13": s["19"]["2026-10-13"]}


class Clock:
    def __init__(self):
        self.now = 1_800_000_000.0

    def __call__(self):
        return self.now


def test_cache_refreshes_hourly_and_serves_last_copy_on_failure():
    clock, calls = Clock(), []

    def fetcher():
        calls.append(clock.now)
        if len(calls) == 2:
            raise ConnectionError("sheet down")
        return SHEET

    cache = hours.HoursCache(fetcher=fetcher, clock=clock)
    first, fetched_at = cache.get()
    clock.now += 60
    assert cache.get() == (first, fetched_at) and len(calls) == 1   # cached

    clock.now += hours.REFRESH_SECONDS
    assert cache.get() == (first, fetched_at) and len(calls) == 2   # failed refresh -> last good copy

    clock.now += 60
    cache.get()
    assert len(calls) == 2                                           # backs off instead of hammering
    clock.now += hours.RETRY_SECONDS
    _, refreshed_at = cache.get()
    assert len(calls) == 3 and refreshed_at != fetched_at


def test_cache_without_a_good_copy_raises():
    cache = hours.HoursCache(fetcher=lambda: "not gviz", clock=Clock())
    with pytest.raises(hours.HoursUnavailable):
        cache.get()


def test_cache_keeps_the_good_copy_when_the_sheet_comes_back_blank():
    clock, calls = Clock(), []
    blank = gviz([["venue", "10/10/2026"], ["Yahentamitsi | Lunch", None]])

    def fetcher():
        calls.append(clock.now)
        return SHEET if len(calls) == 1 else blank

    cache = hours.HoursCache(fetcher=fetcher, clock=clock)
    good = cache.get()
    clock.now += hours.REFRESH_SECONDS
    assert cache.get() == good and len(calls) == 2
    clock.now += 60
    assert cache.get() == good and len(calls) == 2                   # backed off, not stored


def test_cache_backs_off_after_a_failed_first_fetch():
    clock, calls = Clock(), []

    def fetcher():
        calls.append(clock.now)
        if len(calls) == 1:
            raise ConnectionError("sheet down")
        return SHEET

    cache = hours.HoursCache(fetcher=fetcher, clock=clock)
    with pytest.raises(hours.HoursUnavailable):
        cache.get()
    clock.now += 60
    with pytest.raises(hours.HoursUnavailable):
        cache.get()
    assert len(calls) == 1                                           # no fetch during the backoff
    clock.now += hours.RETRY_SECONDS
    assert cache.get()[0] == hours.parse_sheet(SHEET) and len(calls) == 2


def test_stale_copy_is_served_while_another_request_refreshes():
    clock, refreshing, release = Clock(), threading.Event(), threading.Event()
    calls = []

    def fetcher():
        calls.append(clock.now)
        if len(calls) == 2:          # the refresh hangs until the test lets it finish
            refreshing.set()
            release.wait(5)
        return SHEET

    cache = hours.HoursCache(fetcher=fetcher, clock=clock)
    stale = cache.get()
    clock.now += hours.REFRESH_SECONDS
    t = threading.Thread(target=cache.get)
    t.start()
    assert refreshing.wait(5)
    assert cache.get() == stale and len(calls) == 2                  # didn't block or fetch again
    release.set()
    t.join(5)
    assert not t.is_alive()


@pytest.fixture
def sheet_cache(monkeypatch):
    cache = hours.HoursCache(fetcher=lambda: SHEET, clock=Clock())
    monkeypatch.setattr(hours, "cache", cache)
    return cache


async def get_hours(**kwargs):
    kwargs = {"request": None, "start": None, "days": 14, **kwargs}
    # __wrapped__ skips the slowapi decorator, which needs a live Request
    return await routes.get_hours.__wrapped__(**kwargs)


async def test_route_returns_the_requested_window(sheet_cache):
    body = await get_hours(start="2026-10-10", days=4)
    assert body["success"] and body["start"] == "2026-10-10" and body["days"] == 4
    assert body["halls"]["19"] == {
        "2026-10-10": [],
        "2026-10-13": [{"meal": "Dinner", "open": "16:00", "close": "21:00"}],
    }
    assert body["source"] == hours.SOURCE_PAGE and body["fetched_at"]


async def test_route_rejects_bad_start(sheet_cache):
    with pytest.raises(HTTPException) as exc:
        await get_hours(start="10/10/2026")
    assert exc.value.status_code == 400


@pytest.mark.parametrize("start", ["9999-12-31", "0001-01-01"])
async def test_route_rejects_a_start_far_from_today(sheet_cache, start):
    with pytest.raises(HTTPException) as exc:
        await get_hours(start=start, days=60)
    assert exc.value.status_code == 400


async def test_route_is_503_when_the_sheet_never_loaded(monkeypatch):
    monkeypatch.setattr(hours, "cache", hours.HoursCache(fetcher=lambda: "", clock=Clock()))
    with pytest.raises(HTTPException) as exc:
        await get_hours()
    assert exc.value.status_code == 503
