"""Fetch the top 1,000 most-viewed English Wikipedia articles for a month.

These are what people actually look up, so they are the realistic Create inputs —
far better than a hand-written topic list, which only ever contains topics we
already thought of. Writes `tools/create/top1000.txt` (one topic per line).

    python3 tools/create/top1000.py [YYYY/MM]

Non-article rows (Main_Page, Special:Search, Wikipedia:*, "Deaths in 2026", the
`.xyz`-style TLD stubs) are dropped: nobody types them into Create.
"""
import json, re, sys, urllib.request, pathlib

UA = "TidbitsTrivia/1.0 (ben@learningischange.com)"
SKIP_PREFIX = ("Main_Page", "Special:", "Wikipedia:", "Portal:", "Help:", "File:",
               "Talk:", "Category:", "Template:", "User:", "Deaths_in_")


def fetch(period="2026/06"):
    url = (f"https://wikimedia.org/api/rest_v1/metrics/pageviews/top/"
           f"en.wikipedia/all-access/{period}/all-days")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req) as r:
        return json.load(r)["items"][0]["articles"]


def clean(articles):
    out = []
    for a in articles:
        t = a["article"]
        if t.startswith(SKIP_PREFIX):
            continue
        if re.fullmatch(r"\.[a-z]{2,6}", t):      # TLD stubs (.xyz, .xxx)
            continue
        out.append(t.replace("_", " "))
    return out


def main():
    period = sys.argv[1] if len(sys.argv) > 1 else "2026/06"
    topics = clean(fetch(period))
    path = pathlib.Path("tools/create/top1000.txt")
    path.write_text("\n".join(topics) + "\n")
    print(f"{len(topics)} topics -> {path}")


if __name__ == "__main__":
    main()
