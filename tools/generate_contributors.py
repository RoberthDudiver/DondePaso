from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

OWNER_LOGIN = "RoberthDudiver"
REPO_NAME = "DondePaso"
OUTPUT_PATH = Path("assets/community/contributors.json")
OWNER_ROLE = "Creator"
OWNER_SUMMARY = {
    "en": "Creator of DondePaso. Building an honest map of how much of our world we actually explore.",
    "es": "Creador de DondePaso. Construyendo un mapa honesto de cuanto exploramos realmente nuestro entorno.",
}
GRAPHQL_ENDPOINT = "https://api.github.com/graphql"
REST_ENDPOINT = "https://api.github.com"


def _github_headers() -> dict[str, str]:
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise RuntimeError("GITHUB_TOKEN is required to generate contributors.json")

    return {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "User-Agent": "DondePaso-Contributors-Generator",
        "X-GitHub-Api-Version": "2022-11-28",
    }


def _fetch_json(url: str) -> object:
    request = urllib.request.Request(url, headers=_github_headers())
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def _post_graphql(query: str, variables: dict[str, object]) -> dict[str, object]:
    payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    request = urllib.request.Request(
        GRAPHQL_ENDPOINT,
        headers={**_github_headers(), "Content-Type": "application/json"},
        data=payload,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)

    if "errors" in body:
        raise RuntimeError(f"GraphQL error: {body['errors']}")

    return body["data"]


def _iso_or_none(value: str | None) -> str | None:
    return value if value else None


def _max_iso(a: str | None, b: str | None) -> str | None:
    if not a:
        return b
    if not b:
        return a
    return max(a, b)


def _empty_contributor(login: str) -> dict[str, object]:
    return {
        "login": login,
        "name": login,
        "avatarUrl": "",
        "profileUrl": f"https://github.com/{login}",
        "role": "Contributor",
        "summary": None,
        "commits": 0,
        "mergedPrs": 0,
        "changedLines": 0,
        "score": 0,
        "lastContributionAt": None,
        "isOwner": login == OWNER_LOGIN,
    }


def _update_profile(record: dict[str, object], *, login: str, name: str | None, avatar_url: str | None, profile_url: str | None) -> None:
    record["login"] = login
    if name:
        record["name"] = name
    if avatar_url:
        record["avatarUrl"] = avatar_url
    if profile_url:
        record["profileUrl"] = profile_url


def _load_contributors() -> tuple[dict[str, dict[str, object]], list[str]]:
    contributors: dict[str, dict[str, object]] = {}
    recent_logins: list[str] = []
    recent_seen: set[str] = set()

    page = 1
    while True:
        url = f"{REST_ENDPOINT}/repos/{OWNER_LOGIN}/{REPO_NAME}/contributors?per_page=100&page={page}"
        chunk = _fetch_json(url)
        if not isinstance(chunk, list) or not chunk:
            break

        for item in chunk:
            login = item.get("login")
            if not login or str(login).endswith("[bot]"):
                continue
            record = contributors.setdefault(login, _empty_contributor(login))
            _update_profile(
                record,
                login=login,
                name=item.get("login"),
                avatar_url=item.get("avatar_url"),
                profile_url=item.get("html_url"),
            )
            record["commits"] = int(item.get("contributions", 0))
        page += 1

    page = 1
    while len(recent_logins) < 50:
        url = f"{REST_ENDPOINT}/repos/{OWNER_LOGIN}/{REPO_NAME}/commits?per_page=100&page={page}"
        chunk = _fetch_json(url)
        if not isinstance(chunk, list) or not chunk:
            break

        for item in chunk:
            author = item.get("author") or {}
            login = author.get("login")
            if not login or str(login).endswith("[bot]"):
                continue

            record = contributors.setdefault(login, _empty_contributor(login))
            _update_profile(
                record,
                login=login,
                name=author.get("login"),
                avatar_url=author.get("avatar_url"),
                profile_url=author.get("html_url"),
            )

            commit_block = item.get("commit") or {}
            commit_author = commit_block.get("author") or {}
            authored_at = _iso_or_none(commit_author.get("date"))
            record["lastContributionAt"] = _max_iso(
                record.get("lastContributionAt"),
                authored_at,
            )

            if login not in recent_seen:
                recent_seen.add(login)
                recent_logins.append(login)
                if len(recent_logins) >= 50:
                    break
        page += 1

    return contributors, recent_logins


def _load_pr_stats(contributors: dict[str, dict[str, object]]) -> list[str]:
    latest_pr_logins: list[str] = []
    latest_pr_seen: set[str] = set()
    cursor: str | None = None

    query = """
    query($owner: String!, $name: String!, $cursor: String) {
      repository(owner: $owner, name: $name) {
        pullRequests(
          first: 100
          after: $cursor
          states: MERGED
          orderBy: {field: UPDATED_AT, direction: DESC}
        ) {
          nodes {
            mergedAt
            additions
            deletions
            author {
              login
              avatarUrl
              url
              ... on User {
                name
              }
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
    """

    while True:
        data = _post_graphql(
            query,
            {"owner": OWNER_LOGIN, "name": REPO_NAME, "cursor": cursor},
        )
        pull_requests = data["repository"]["pullRequests"]
        nodes = pull_requests["nodes"]

        for node in nodes:
            author = node.get("author") or {}
            login = author.get("login")
            if not login or str(login).endswith("[bot]"):
                continue

            record = contributors.setdefault(login, _empty_contributor(login))
            _update_profile(
                record,
                login=login,
                name=author.get("name") or login,
                avatar_url=author.get("avatarUrl"),
                profile_url=author.get("url"),
            )
            record["mergedPrs"] = int(record.get("mergedPrs", 0)) + 1
            record["changedLines"] = int(record.get("changedLines", 0)) + int(node.get("additions", 0)) + int(node.get("deletions", 0))
            record["lastContributionAt"] = _max_iso(
                record.get("lastContributionAt"),
                _iso_or_none(node.get("mergedAt")),
            )

            if login not in latest_pr_seen:
                latest_pr_seen.add(login)
                latest_pr_logins.append(login)

        page_info = pull_requests["pageInfo"]
        if not page_info["hasNextPage"]:
            break
        cursor = page_info["endCursor"]

    return latest_pr_logins


def _load_owner_profile(contributors: dict[str, dict[str, object]]) -> dict[str, object]:
    owner_response = _fetch_json(f"{REST_ENDPOINT}/users/{OWNER_LOGIN}")
    record = contributors.setdefault(OWNER_LOGIN, _empty_contributor(OWNER_LOGIN))
    _update_profile(
        record,
        login=OWNER_LOGIN,
        name=owner_response.get("name") or OWNER_LOGIN,
        avatar_url=owner_response.get("avatar_url"),
        profile_url=owner_response.get("html_url"),
    )
    record["role"] = OWNER_ROLE
    record["summary"] = OWNER_SUMMARY
    record["isOwner"] = True
    return record


def _score(record: dict[str, object]) -> int:
    merged_prs = int(record.get("mergedPrs", 0))
    commits = int(record.get("commits", 0))
    changed_lines = int(record.get("changedLines", 0))
    return merged_prs * 10 + commits * 3 + round(changed_lines / 200)


def _sort_key(record: dict[str, object]) -> tuple[object, ...]:
    if record.get("isOwner"):
        return (0, 0, 0, 0, "", "")
    last_contribution = record.get("lastContributionAt") or ""
    return (
        1,
        -int(record.get("score", 0)),
        -int(record.get("mergedPrs", 0)),
        -int(record.get("commits", 0)),
        str(last_contribution),
        str(record.get("login", "")),
    )


def _serialize(record: dict[str, object], rank: int) -> dict[str, object]:
    return {
        "rank": rank,
        "login": record["login"],
        "name": record["name"],
        "avatarUrl": record["avatarUrl"],
        "profileUrl": record["profileUrl"],
        "role": record["role"],
        "summary": record["summary"],
        "commits": int(record.get("commits", 0)),
        "mergedPrs": int(record.get("mergedPrs", 0)),
        "changedLines": int(record.get("changedLines", 0)),
        "score": int(record.get("score", 0)),
        "lastContributionAt": record.get("lastContributionAt"),
        "isOwner": bool(record.get("isOwner", False)),
    }


def main() -> int:
    contributors, recent_commit_logins = _load_contributors()
    latest_pr_logins = _load_pr_stats(contributors)
    owner_record = _load_owner_profile(contributors)

    for record in contributors.values():
        record["score"] = _score(record)

    owner_record["score"] = max(int(owner_record.get("score", 0)), 1)

    ranked_records = sorted(contributors.values(), key=_sort_key)
    ranking = [_serialize(record, index) for index, record in enumerate(ranked_records, start=1)]
    rank_lookup = {
        item["login"]: item["rank"]
        for item in ranking
    }

    latest_order: list[str] = []
    latest_seen: set[str] = set()
    for source in (recent_commit_logins, latest_pr_logins):
        for login in source:
            if login in latest_seen:
                continue
            latest_seen.add(login)
            latest_order.append(login)
            if len(latest_order) >= 50:
                break
        if len(latest_order) >= 50:
            break

    if len(latest_order) < 50:
        for record in sorted(
            contributors.values(),
            key=lambda item: str(item.get("lastContributionAt") or ""),
            reverse=True,
        ):
            login = str(record["login"])
            if login in latest_seen:
                continue
            latest_seen.add(login)
            latest_order.append(login)
            if len(latest_order) >= 50:
                break

    latest_contributors = [
        _serialize(contributors[login], rank_lookup.get(login, 0))
        for login in latest_order
        if login in contributors
    ]

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "repository": {
            "owner": OWNER_LOGIN,
            "name": REPO_NAME,
            "url": f"https://github.com/{OWNER_LOGIN}/{REPO_NAME}",
        },
        "owner": _serialize(owner_record, 1),
        "ranking": ranking,
        "latestContributors": latest_contributors,
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, urllib.error.HTTPError, urllib.error.URLError) as exc:
        print(f"Contributor generation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
