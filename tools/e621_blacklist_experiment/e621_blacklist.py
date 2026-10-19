"""
e621 tag blacklist: read and update the blacklist on YOUR OWN e621 account.

e621 stores each account's tag blacklist as a single multi-line string on that user's profile
(the same text box as Settings -> Blacklisted Tags on e621.net). Each line is one blacklist entry;
an entry can be a single tag ("young") or several tags separated by spaces, which e621 treats as an
AND ("rating:e young") -- a post is blacklisted if ALL tags on that line match it.

Both reading and writing go through e621's /users/<id>.json endpoint, authenticated as that same
account -- there is no separate "blacklist" endpoint, and no way to add a single entry server-side
without resending the full list.

Requirements, both enforced by e621:
  - A descriptive User-Agent identifying your app and a way to contact you, e.g.
    "my-app/1.0 (by SomeUsername)". Generic or default User-Agents get blocked.
  - HTTP Basic Auth using your e621 USERNAME and an API KEY (My Account -> API Access on
    e621.net), never your login password.
  - You can only read or edit the blacklist of the account you're authenticated as.

Install: pip install requests
"""
from __future__ import annotations

import requests

BASE_URL = "https://e621.net"
USER_AGENT = "blacklist-experiment/1.0 (by Nyjako)"


def _session(username: str, api_key: str) -> requests.Session:
    s = requests.Session()
    s.auth = (username, api_key)
    s.headers["User-Agent"] = USER_AGENT
    return s


def get_blacklisted_tags(username: str, api_key: str) -> list[str]:
    """Return the account's current blacklist as a list of entries, one per line.

    e621's profile JSON only includes `blacklisted_tags` when you're authenticated as the account
    you're asking about, so `username` here must be the account the api_key belongs to.
    """
    s = _session(username, api_key)
    resp = s.get(f"{BASE_URL}/users/{username}.json")
    resp.raise_for_status()
    raw = resp.json().get("blacklisted_tags") or ""
    return [line for line in raw.splitlines() if line.strip()]


def save_blacklisted_tags(username: str, api_key: str, tags: list[str]) -> None:
    """Replace the account's ENTIRE blacklist with `tags` (one entry per line).

    There's no "add one entry" call on e621's side -- the list is a single field, so adding a tag
    really means: read the current list, add the new entry, write the full list back. That's what
    add_blacklisted_tag() below does; call this directly only if you already have the complete list
    you want saved (e.g. you're also removing or reordering entries).
    """
    s = _session(username, api_key)
    who = s.get(f"{BASE_URL}/users/{username}.json")
    who.raise_for_status()
    user_id = who.json()["id"]

    resp = s.patch(f"{BASE_URL}/users/{user_id}.json", json={"user": {"blacklisted_tags": "\n".join(tags)}})
    resp.raise_for_status()


def add_blacklisted_tag(username: str, api_key: str, new_entry: str) -> list[str]:
    """Add one new entry (a tag, or a space-separated AND group like 'rating:e young') without
    disturbing what's already there. Returns the full blacklist after saving."""
    current = get_blacklisted_tags(username, api_key)
    if new_entry not in current:
        current.append(new_entry)
        save_blacklisted_tags(username, api_key, current)
    return current


if __name__ == "__main__":
    USERNAME = "YourE621Username"
    API_KEY = "your-api-key-here"

    print("Current blacklist:")
    for entry in get_blacklisted_tags(USERNAME, API_KEY):
        print(" ", entry)

    updated = add_blacklisted_tag(USERNAME, API_KEY, "example_new_tag")
    print("\nBlacklist after adding 'example_new_tag':")
    for entry in updated:
        print(" ", entry)
