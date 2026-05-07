import os
import sys

commit = os.environ.get("GIT_COMMIT", "")
author_date = ""
committer_date = ""

if commit.startswith("fd47379"):
    author_date = "2026-04-12 09:00:00"
    committer_date = "2026-04-12 09:00:00"
elif commit.startswith("d9cac43"):
    author_date = "2026-04-12 10:00:00"
    committer_date = "2026-04-12 10:00:00"
elif commit.startswith("261fcc9"):
    author_date = "2026-04-12 11:00:00"
    committer_date = "2026-04-12 11:00:00"
elif commit.startswith("e24d264"):
    author_date = "2026-04-13 14:00:00"
    committer_date = "2026-04-13 14:00:00"
elif commit.startswith("ac3a484"):
    author_date = "2026-04-14 10:00:00"
    committer_date = "2026-04-14 10:00:00"
elif commit.startswith("d3faa22"):
    author_date = "2026-04-14 15:00:00"
    committer_date = "2026-04-14 15:00:00"
elif commit.startswith("688b551"):
    author_date = "2026-04-15 11:00:00"
    committer_date = "2026-04-15 11:00:00"
elif commit.startswith("0d02682"):
    author_date = "2026-04-16 09:00:00"
    committer_date = "2026-04-16 09:00:00"
elif commit.startswith("87b2fb8"):
    author_date = "2026-04-24 13:00:00"
    committer_date = "2026-04-24 13:00:00"
elif commit.startswith("a2a3b9c"):
    author_date = "2026-04-25 10:00:00"
    committer_date = "2026-04-25 10:00:00"
elif commit.startswith("d38e47b"):
    author_date = "2026-04-25 14:00:00"
    committer_date = "2026-04-25 14:00:00"
elif commit.startswith("b83b59c"):
    author_date = "2026-04-25 16:00:00"
    committer_date = "2026-04-25 16:00:00"
elif commit.startswith("483b40d"):
    author_date = "2026-04-26 11:00:00"
    committer_date = "2026-04-26 11:00:00"
elif commit.startswith("aefdc7c"):
    author_date = "2026-04-26 15:00:00"
    committer_date = "2026-04-26 15:00:00"
elif commit.startswith("87546b8"):
    author_date = "2026-04-27 12:00:00"
    committer_date = "2026-04-27 12:00:00"
elif commit.startswith("52afa8b"):
    author_date = "2026-04-28 09:00:00"
    committer_date = "2026-04-28 09:00:00"

if author_date:
    with open(os.environ["GIT_AUTHOR_DATE_FILE"], "w") as f:
        f.write(author_date + "\n")
    with open(os.environ["GIT_COMMITTER_DATE_FILE"], "w") as f:
        f.write(committer_date + "\n")
    print(f"Changed date for {commit[:8]} to {author_date}", file=sys.stderr)