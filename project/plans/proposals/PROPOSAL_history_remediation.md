# Design Proposal — removing third-party material from published history

**Status:** proposal, 2026-09-12. Phase 0 (Design). **Nothing has been executed.**
**Scope:** SwiftXLSX, BusinessMathExcel, BusinessMath. SwiftZIP, SwiftExcelCore and
SwiftExcelFunctions need no history change.
**Character:** this is a **runbook for an irreversible operation across public remotes.** It is
written to be followed step by step, and every destructive command is preceded by the check that
justifies it.

---

## 1. Objective

**Stop publishing material that is not ours to publish, and do it without breaking the family.**

Three distinct problems, three different remedies. The asymmetry is the whole design: treating
them uniformly would either under-fix the serious one or destroy 1,022 commits of reasoning to
fix a lesser one.

---

## 2. What was found, and how far it is verified

| # | Finding | Where | Verified by |
|---|---|---|---|
| 1 | **Third-party client material** — a wireless protocol specification, a patent PDF, 44 device screenshots, a draft email to a named external contact | SwiftXLSX (88 path-mentions, 27 tags), BusinessMathExcel (90, 4 tags) | **Directly.** Blob `c715b858` fetched from a commit reachable from `origin/main`; its first line is the protocol document's title |
| 2 | **~90 MB of third-party books**, incl. a commercially sold ebook | BusinessMath, **tracked on `main` now**, added `ca7afd83` (2026-08-04) | **Directly.** 27 files, 90.1 MB measured under `project/library/` |
| 3 | Numerical Recipes code in three CF kernels | BusinessMath | **Not verified** — no copy of NR to diff. §11.1 |
| 4 | Every released tag ships MIT, not AGPL | all six | **Directly.** `git show v3.0.0-alpha.3:LICENSE` → `MIT License` |

**Findings 1 and 2 are what this proposal remediates.** 3 is a code rewrite and must not ride
along (§11.1). 4 is resolved as a byproduct, since new tags carry the new licence.

### 2.1 The single most important fact

**No repository has a fork. None has an open issue.** Verified across all six.

That is unusually good news, and it is what makes removal *effective* rather than theatrical. A
fork would hold the objects independently and beyond reach; there are none. Only GitHub's own
object store has to be dealt with.

---

## 3. Why three treatments

| Repo | Stars | Created | Commits | Tags | What is wrong | Treatment |
|---|---:|---|---:|---:|---|---|
| SwiftXLSX | 0 | 2026-05-30 | 70 | 27 | **a third party's** confidential data | **delete & recreate** |
| BusinessMathExcel | 0 | 2026-05-30 | 136 | 4 | same | **delete & recreate** |
| BusinessMath | **13** | **2022-03-21** | **1,022** | **108** | **our own** copyright liability | **surgical path excision** |

Three arguments drive the split:

1. **Whose interests are at stake.** The client material belongs to someone else and documents their
   hardware. That deserves the method that actually removes the objects rather than merely
   dereferencing them. The books are our own infringement — serious, but the injured parties are
   publishers whose remedy is that we stop, not that no trace ever existed.
2. **What deletion costs.** For the two four-month-old repos with zero stars, zero forks and zero
   issues, delete-and-recreate costs **nothing measurable**. For BusinessMath it would cost 13
   stars, four years of repo age, 108 tags and — most of all — **1,022 commits whose messages are
   a substantial part of this project's value.**
3. **How concentrated the problem is.** §4 measures it: in BusinessMath the material is one path,
   introduced at one commit, contained in **20 of 108 tags**. That is excisable. In the other two
   it is interleaved with a scaffolding refactor across the whole life of the repo.

---

## 4. Measured blast radius

### 4.1 BusinessMath — the problem is narrower than it looks

```
adding commit:        ca7afd83  "refactor: adopt v2 guidelines layout"  2026-08-04
tags containing it:   20 of 108
newest CLEAN tag:     v2.5.1
```

The 20 affected tags:

```
v2.5.2  v2.6.0  v2.7.0  v2.8.0  v2.9.0
v2.10.0 v2.10.1 v2.11.0 v2.11.1 v2.12.0 v2.12.1 v2.13.0
v2.14.0 v2.15.0 v2.16.0 v2.17.0 v2.18.0
v3.0.0-alpha.1  v3.0.0-alpha.2  v3.0.0-alpha.3
```

**88 tags — everything at or below `v2.5.1` — are clean and must not be touched.** Note that the
affected set is *not* a contiguous version range: `v2.5.2` is affected while `v2.5.0` and
`v2.5.1` are not, which means tags were applied out of version order at some point. Any script
that assumes "everything above vX" is wrong; **use `git tag --contains` and nothing else.**

Size: 90.1 MB of a 150 MB `.git` is the books.

### 4.2 Who pins what — every one of these breaks

```
BusinessMathExcel   → businessmath 2.15.0        @ be704795   ← AFFECTED tag
                    → swiftxlsx 0.23.1           @ f4d78d9a   ← repo being recreated
SwiftExcelFunctions → businessmath 3.0.0-alpha.3 @ b0dcaf1b   ← AFFECTED tag
                    → swiftxlsx 0.24.1           @ 277392cd   ← repo being recreated
```

**SwiftExcelFunctions is not being rewritten and will still break**, because it pins revisions in
two repos that are. It must be re-pinned in the same operation.

---

## 5. The three hazards

### 5.1 SwiftPM fingerprints — the documented trap, and the reason not to reuse a version

`CLAUDE.md` already records this: SwiftPM keeps a trust-on-first-use fingerprint per version at
`~/.swiftpm/security/fingerprints/<package>-<hash>.json`, and a version whose revision changes
fails every subsequent resolve with *"does not match previously recorded value"* until the record
is corrected.

Measured on this machine alone:

| Package | Versions recorded |
|---|---:|
| businessmath | **19** |
| swiftxlsx | **25** |
| swiftexcelcore | 8 |
| swiftzip | 3 |
| swiftexcelfunctions | 3 |

Every one of those is a landmine if the same version number is re-pointed at a new commit — and
on every other machine and CI runner that ever resolved them, which we cannot reach.

**Governing rule for this whole operation: no version number may ever point at two different
commits.** That single constraint determines most of §6 and §7.

### 5.2 Unreferenced objects survive a force-push

After a force-push, GitHub keeps the old objects and they remain fetchable **by direct SHA** until
garbage collected, which for a public repo requires asking GitHub Support to expire them. A
force-push therefore does not, on its own, remove anything — it only stops it being *found*.

This is precisely why the two affected repos get deleted rather than rewritten. Deleting the repository
destroys its object store.

### 5.3 There is no undo

Everything below is irreversible on the remote. §9 requires a full local mirror of all six repos
**before any destructive step**, and §10 states what a rollback can and cannot recover.

---

## 6. Procedure A — SwiftXLSX and BusinessMathExcel (delete & recreate)

### A0 — Pre-flight

```bash
# Full mirror backups, OUTSIDE the working trees. Do not skip.
mkdir -p ~/repo-backups/2026-09-12
for r in SwiftXLSX BusinessMathExcel BusinessMath SwiftZIP SwiftExcelCore SwiftExcelFunctions; do
  git clone --mirror "git@github.com:jpurnell/$r.git" ~/repo-backups/2026-09-12/$r.git
done
du -sh ~/repo-backups/2026-09-12/*        # confirm each is non-trivial
```

Confirm working trees are clean and that no other session holds uncommitted work
(§11.3 — two sessions were active in these repos during this session).

### A1 — Curate the tree

Per repo, from the current `main` working tree:

```bash
git rm -r --cached "project/library"              # keep .gitkeep only if wanted
git rm --cached ".claude/settings.local.json"     # tracked in both; ~30 lines of absolute paths
printf '.claude/settings.local.json\nproject/library/*\n!project/library/.gitkeep\n' >> .gitignore
```

Then fix the leaks that are content rather than history:

- `.quality-gate.yml` — replace the hardcoded `corpusPath: /Users/jpurnell/...` with an
  environment variable (`SwiftXLSX:9`, `BusinessMathExcel:10`)
- verify no client-identifying string remains: grep for the client name (recorded in the private
  mirror and the handoff, deliberately **not** written here — see §6.2)

### A2 — Build the fresh history

```bash
# From a pristine export of the curated tree, not the old .git
mkdir /tmp/fresh-SwiftXLSX && git archive HEAD | tar -x -C /tmp/fresh-SwiftXLSX
cd /tmp/fresh-SwiftXLSX
git init -b main
git add -A
git commit -m "<see §6.1 for what this message must say>"
```

### A3 — Replace the remote

```bash
gh repo delete jpurnell/SwiftXLSX --yes          # IRREVERSIBLE
gh repo create jpurnell/SwiftXLSX --public \
  --description "..." --source . --push
```

### A4 — Tag at a *fresh* version

Never reuse a number (§5.1). Old tags are gone with the repo, so the next tag must be **above**
everything previously published:

| Repo | Highest old tag | New tag |
|---|---|---|
| SwiftXLSX | v0.24.1 | **v0.25.0** |
| BusinessMathExcel | v0.8.0 | **v0.9.0** |

### 6.1 What the initial commit message must contain

A single "Initial commit" on a repo that demonstrably existed since May would be dishonest, and
anyone reading the history will notice the gap. The message should state plainly that history was
replaced, when, and why — without naming the third party, since the point is to stop publishing
their material.

Proposed content: that this repository's history was rebuilt on 2026-09-12; that the previous
history contained material belonging to an unrelated project which was never ours to publish;
that the code is unchanged and the prior released versions are superseded rather than
reachable; and that `CHANGELOG.md` (which is carried forward) remains the record of what changed
when.

### 6.2 This document does not name the client, and that was a correction

The first draft of this proposal named the client eight times — the company, the fact that the
asset is a wireless protocol specification, and a verbatim quotation of the protocol document's
title — in a file **tracked in a public repository.** §6.1 of that same draft argued the initial
commit message should avoid naming them "since the point is to stop publishing their material."

It was caught before the commit was pushed, which was luck rather than diligence. The lesson is
narrow and worth stating: **a remediation document is itself a publication.** Writing down what
was exposed, in the repository that exposed it, recreates the exposure in a form nobody thinks to
audit.

So: the client name lives in the private mirror at `~/repo-backups/2026-09-12/` and in the
handoff, and the verification commands here take it as `$CLIENT` from the environment rather than
carrying it inline.

**Related, and still outstanding:** the client's name also appears in BusinessMath's *tracked and
already-published* planning documents — `project/plans/proposals/PROPOSAL_agreement_statistics.md`,
`project/plans/completed/INTERPOLATION_PLAN.md`, `project/summaries/2026-04-07_v2.1.2_InterpolationModule.md`
and several others. Name only, no protocol detail, but it is on a public repo and the
`filter-repo` pass is the natural moment to deal with it. Those references are historical
attributions in planning prose and can be generalised without losing meaning.

**Carry `CHANGELOG.md` and `project/summaries/` forward.** They are the substitute for the
history being discarded, and they are already good.

---

## 7. Procedure B — BusinessMath (surgical)

### B1 — Excise the path from history

```bash
cd ~/repo-backups/2026-09-12/BusinessMath.git   # operate on a COPY first, verify, then the real one
git filter-repo --path project/library/ --invert-paths
```

`filter-repo` rewrites every commit that touched the path and leaves the other ~1,000 alone.
Verify before going near the remote:

```bash
git log --all --pretty=format: --name-only | sort -u | grep -c "^project/library/"   # expect 0
git count-objects -vH | grep size-pack                                              # expect ~60MB not ~150MB
git log --oneline | wc -l                                                           # expect ~1022 still
git tag --contains $(git rev-list --max-parents=0 HEAD) | wc -l                     # tags survive
```

### B1a — Dry run, 2026-09-12: one prediction was wrong, and the fix is *not* to push the rewritten tags

Run on a scratch mirror before going near the remote. Results:

| | Before | After | Predicted |
|---|---|---|---|
| commits on `main` | 1,023 | **1,023** | preserved ✅ |
| `size-pack` | 140.64 MiB | **60.51 MiB** | ~60 MB ✅ |
| `project/library/` paths in all history | 13 | **0** | 0 ✅ |
| tags whose SHA moved | — | **95 of 108** | **20** ❌ |

**The tag prediction was wrong, and the reason is not the path filter.** `v2.5.1` moved despite
predating the offending commit, and the 13 tags that *didn't* move are exactly the oldest —
`1.0.0`–`1.0.8`, `v0.1.0-alpha`, `v0.99-beta`, `v2.0.0`, `v2.0.1`, `v2.1.0`.

Cause: **62 of 1,367 commits are GPG-signed.** Any rewrite strips the `gpgsig` header, which
changes those commit objects, which changes every descendant's SHA. The first signed commit sits
early in the 2.x line, so everything after it moves. Narrowing the path filter cannot help —
only 4 commits touch `project/library/` at all, and 1 touches the books.

**Why this does not matter:** the rewritten tags must not be pushed at all.

Verified directly — **all 88 clean tags carry zero `project/library/` content**, scanned one by
one with `ls-tree -r`. The remote's existing copies of those 88 are already book-free, at their
original SHAs, with their signatures intact. So:

> **Push the rewritten `main`. Delete the 20 affected tags. Leave the other 88 exactly as they
> already are on the remote, and never push their rewritten local counterparts.**

Git is content with tags pointing at commits outside `main`'s ancestry, so the 88 old tags keep
their original history alive — and that history contains no books. The commits between the last
clean tag and the old `main` tip become unreferenced, which is what the §B4 Support request
expires.

The original §4.1 framing — "20 of 108 affected" — is still the right number for *what must be
deleted*. It was simply wrong about what `filter-repo` does to the rest, and the correction only
became visible by dry-running it.

### B1b — Executed 2026-09-12: `main` and tags are **not** all the refs

The operation was declared finished once, wrongly. `main` was rewritten and pushed, the 20
affected tags were deleted, the 88 clean tags were confirmed at their original SHAs — and a fresh
clone of the remote still reported **27 `project/library` paths and 141 MiB.**

**Three branches still carried the books:**

```
feature/gpu-seeded-acceleration        27 book paths
feature/stage-6-template-delegation    27
fix/flaky-batch-benchmark              27
```

`filter-repo` had already cleaned all six branches in the mirror. They were simply never pushed,
because every step of this document was written in terms of `main` and tags. The repository has
six branches; the plan accounted for one.

**The fix, and the rule:**

```bash
git push --force origin 'refs/heads/*:refs/heads/*'   # every branch
# tags are handled separately and deliberately — see §B1a
```

> **Enumerate refs; do not assume them.** `git for-each-ref` is the authority on what a repository
> publishes. `git branch -r` and `git tag` each answer half the question, and a remediation that
> asks only half of it reports success while still publishing the material.

The honest verification is a **fresh clone of the remote**, not any local check. Every local
signal was green while three branches were still dirty: the local mirror had been filtered, so it
was clean by construction and could not have revealed the problem. Only
`git for-each-ref --contains <commit>` on a newly cloned copy found it.

### B1c — `git fetch` does not prune tags, and that can undo the whole operation

Reported by the BusinessMath session immediately after resetting, and it is the §B1b miss one
level further out.

After fetching the rewritten history it still held **109 local tags** — including all 20 deleted
ones, still pointing at old-history commits that still contain the 90 MB. `git fetch` prunes
neither branches nor tags by default. **A single `git push --tags` from any such clone
resurrects everything.**

```bash
git fetch --prune --prune-tags origin    # 109 → 89, matching the remote
git reset --hard origin/main
```

**Both halves are required.** A plain `reset --hard` fixes the branch and leaves the resurrection
hazard in place.

> **A history rewrite is not complete when the remote is clean. It is complete when every clone
> that fetched beforehand has been pruned** — and those clones are, by definition, the ones you
> cannot enumerate.

Checked on this machine after the BusinessMath rewrite:

| Clone | Tags | Holds deleted tags |
|---|---:|---|
| live working repo | 89 | no — pruned |
| `~/repo-backups/2026-09-12/` mirror | 108 | **yes, by design** — it is the backup |
| self-hosted runner `_work` | — | no BusinessMath checkout |

Clean here. **Not verifiable elsewhere**: other machines, cloud sessions, and any CI with a
persistent workspace each hold the deleted tags until pruned. That belongs in the handoff, not
in a checklist item that can be ticked.

### Two cosmetic consequences, recorded so they are not mistaken for faults

- **19 surviving tags, `v2.5.1` among them, are no longer ancestors of the new `main`.**
  `filter-repo` forked the chain slightly earlier than the offending commit. They resolve, their
  SHAs are unchanged, and none carries the books — it only means `git log v2.5.1..main` shows the
  whole rewritten history as new.
- **`project/library/` survives as an empty directory holding a `.DS_Store`.** Untracked and
  gitignored, so harmless, but it will sit there indefinitely.

### B2 — The tag decision, which is the one real choice here

`filter-repo` rewrites the 20 affected tags to new SHAs **under the same version numbers**. That
is exactly the fingerprint trap of §5.1. Three ways out, and they are not equivalent:

| | Approach | Books removed? | Version reused at a new SHA? | Cost |
|---|---|---|---|---|
| **B2a** | re-push all 20 rewritten tags under the same names | ✅ | **yes — 20 of them** | every machine that resolved any of those 19 recorded versions fails until its fingerprint file is deleted; unreachable CI included |
| **B2b** | **delete the 20 affected tags; cut one fresh tag above them** | ✅ | no | those 20 released versions become unavailable; failure is a clear "version not found" |
| B2c | rewrite `main` only, leave the 20 tags | ❌ **no** | no | the books stay published via tags. Not a remedy. |

**Recommend B2b**, on the §5.1 rule. Its cost falls almost entirely on our own repos, which are
being re-pinned in this same operation anyway, and all **88 clean tags at or below `v2.5.1`
survive untouched** — so any third party pinning an older version is unaffected.

**But B2b's cost depends on a fact not yet measured:** whether anything outside this account
depends on one of those 20 versions. 13 stars and no forks makes it unlikely, not impossible.

> **Pre-flight check, before choosing:** open
> `https://github.com/jpurnell/BusinessMath/network/dependents`. If it lists nothing outside this
> account, take **B2b**. If it lists a real external dependent on an affected version, take
> **B2a** and publish the fingerprint-deletion instruction with the release notes.

New tag after excision: **`v3.0.0-alpha.4`** (above `v3.0.0-alpha.3`, never previously used).

### B3 — Push

```bash
git push --force origin main                                  # rewritten main ONLY
git push origin --delete v2.5.2 v2.6.0 ... v3.0.0-alpha.3     # the exact 20, from `tag --contains`
git push origin v3.0.0-alpha.4                                # fresh, never previously used
```

**Do not use `git push --mirror` or `--tags`.** Either would overwrite the 88 clean tags with
their rewritten counterparts, needlessly moving 88 version numbers to new SHAs and tripping every
fingerprint record for them — the precise failure §5.1 exists to prevent. See §B1a.

### B4 — Ask GitHub to expire the old objects

A force-push leaves them fetchable by SHA (§5.2). Open a Support request naming the repository
and asking for unreferenced objects to be garbage collected. **Until that completes, the books
remain retrievable by anyone who recorded a SHA.**

---

## 8. Procedure C — re-pin the family, in dependency order

Bottom-up, because each step's verification depends on the one below it resolving.

```
SwiftZIP (untouched) → SwiftExcelCore (untouched) → SwiftXLSX (new v0.25.0)
    → SwiftExcelFunctions (re-pin swiftxlsx + businessmath, new tag)
        → BusinessMathExcel (recreated; pin everything new, new v0.9.0)
```

| # | Repo | Change |
|---|---|---|
| C1 | SwiftXLSX | already at v0.25.0 from A4 |
| C2 | BusinessMath | already at v3.0.0-alpha.4 from B2 |
| C3 | SwiftExcelFunctions | `Package.swift`: swiftxlsx → `.upToNextMinor(from: "0.25.0")`; businessmath → `.upToNextMinor(from: "3.0.0-alpha.4")`. Delete `Package.resolved`, re-resolve, build, test, gate, tag **v0.8.0** |
| C4 | BusinessMathExcel | pin all of the above; re-resolve; build; test; gate; tag **v0.9.0** |

Delete the stale fingerprint records for any package whose revision moved, on this machine:

```bash
rm ~/.swiftpm/security/fingerprints/businessmath-*.json
rm ~/.swiftpm/security/fingerprints/swiftxlsx-*.json
```

---

## 9. Verification — how we know it worked

Each of these is a command with an expected answer, not an impression:

```bash
# 0. FIRST: no ref of any kind still reaches the offending commit. This is the check
#    that would have caught the three missed branches (§B1b). Run it on a FRESH clone.
git clone --mirror <remote> /tmp/probe.git
git -C /tmp/probe.git for-each-ref --contains <offending-commit> | wc -l      # expect 0

# 1. No client-identifying string survives anywhere, in any commit, in any repo
for r in SwiftXLSX BusinessMathExcel BusinessMath; do
  git -C $r log --all --pretty=format: --name-only | sort -u | grep -ci "$CLIENT"   # expect 0
done

# 2. The specific blob is gone from the remote
git ls-remote git@github.com:jpurnell/SwiftXLSX.git | grep c715b858              # expect empty
cd /tmp && git clone --mirror git@github.com:jpurnell/SwiftXLSX.git probe.git
git -C probe.git cat-file -e c715b858 2>&1                                       # expect "not a valid object"

# 3. No books in BusinessMath history
git -C BusinessMath log --all --pretty=format: --name-only | sort -u \
  | grep -cE "project/library/.*\.(pdf|docx|html)$"                              # expect 0

# 4. No version number points at two commits — compare old mirror to new remote
#    for every version present in both, revisions must MATCH or the version must be ABSENT

# 5. Every repo resolves, builds, tests, and gates clean
# 6. Licence at the new tags is AGPL/Apache, not MIT
git show v3.0.0-alpha.4:LICENSE | head -2                                        # expect AGPL
```

---

## 10. What this does **not** fix

Stated plainly, because a remediation that oversells itself is worse than one that admits limits:

- **Anything already cloned.** Unknowable and unrecallable. For the client material, assume a
  copy could exist somewhere and that removal reduces rather than eliminates exposure.
- **GitHub's caches until Support acts** (§5.2, §B4). For BusinessMath the window is real.
- **Search-engine and archive caches** of the rendered file views.
- **The Numerical Recipes finding** — §11.1, separate work.
- **The already-released MIT versions.** Finding 4 cannot be undone for anyone holding a tag; new
  tags carry the new licence, old MIT grants stand.
- **Whether the 44 screenshots contain biometric or personal data.** Nobody has looked. §11.2.

---

## 11. Open questions and decisions needed

1. **Numerical Recipes must be confirmed before rewriting.** Three functions
   (`besselK01Steed`, `besselSteedPQ`, `continuedFractionBeta`) look transcribed on
   identifier-correspondence evidence, judged **without a copy of NR to diff against**. Two were
   committed 2026-09-11, so they sit near the tip and are cheap to fix. **Do not fold this into
   the history operation** — it is a code change, it needs independent confirmation, and mixing it
   in would make a large irreversible step depend on an unverified claim.
2. **Should someone look at the 44 screenshots first?** They are device readouts from a
   biofeedback product. If they contain biometric data or PII the disclosure calculus changes, and
   that judgement should be made by a person before the evidence is destroyed. **Consider
   preserving them in the private mirror even after removal**, for exactly that reason.
3. **Does the client need telling?** Not a technical question. The material was published for roughly
   a month on a public repository with zero forks. Whatever the answer, the mirror backup is the
   record of what was exposed and for how long.
4. **B2a or B2b** — decided by the dependents check in §B2.
5. **SwiftZIP's committed `.build`** (2,936 blobs, 29 MB) is untidy, not a liability. Left alone
   deliberately; folding a cosmetic cleanup into this operation adds risk for no gain.
6. **Does the `project/library/` convention survive at all?** It is a scaffolding directory that
   accumulated other people's PDFs in two separate repos. The safest fix is not to gitignore it
   better but to **stop having it** — keep reference material outside every repository.
