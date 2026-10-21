# Release Process

When the user says they're ready for a release (e.g. "ready for a release", "let's prepare a
release", "release version X.Y.Z"), carry out these steps:

1. **Determine the version**: If no explicit version number was given, suggest a sensible next
   version based on the commits since the last git tag (patch for bug fixes, minor for new
   features), and briefly ask for confirmation before proceeding.

2. **Update `.toc`**: Set `## Version:` in `SmuveUI.toc` to the new version.

3. **Maintain `CHANGELOG.md`**: Insert a new section right below the heading:

   ```
   ## <version> - <YYYY-MM-DD>
   - <change 1>
   - <change 2>
   ```

   Derive the entries from `git log <last-tag>..HEAD --oneline`, but phrase them as readable,
   user-facing sentences - no raw commit messages, no internal refactoring details that are
   irrelevant to CurseForge users. The changelog must be written **in English** (CurseForge
   audience).

4. **Commit**: commit message `Release <version>`, containing the `.toc` and `CHANGELOG.md`
   changes.

5. **Tag**: create an annotated git tag exactly matching the version number, **without a "v"
   prefix** (e.g. `0.2.0`) - this tag is passed 1:1 as `project-version` to the CurseForge
   pipeline (BigWigsMods/packager).

6. **Mandatory checklist before every push**: never push without checking this first:
   - Has the version in `SmuveUI.toc` actually been bumped since the last tag? If not, do that
     first (step 2) - never push with an unchanged version.
   - Show the user the new `CHANGELOG.md` section and wait for their explicit confirmation
     (review) before proceeding.
   - Only then: `git push && git push --tags`. This automatically triggers the CurseForge upload
     via the GitHub Action (trigger: tags only, not regular pushes to `main`).

`.pkgmeta` uses `manual-changelog`, meaning the packager uploads the exact content of
`CHANGELOG.md` to CurseForge instead of generating one from the git log automatically - step 3 is
therefore important for a clean changelog on CurseForge.
