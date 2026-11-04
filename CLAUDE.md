# Reference Addons

SmuveUI targets "WoW Forever," an official Blizzard WoW client/version that adds its own non-stock
APIs/enums beyond retail or classic Blizzard's. When a stock Blizzard API seems to silently fail or
not expose something the default UI clearly does, don't conclude it's impossible from that alone -
check how one of these known-working addons for this same client solves the identical problem
first, by reading its source directly (`gh api repos/<owner>/<repo>/contents/<path>` + base64
decode, or `WebFetch` on the raw file):

- **EllesmereUI** - <https://github.com/EllesmereGaming/EllesmereUI>
- **BetterBlizzPlates** - <https://github.com/Bodify/BetterBlizzPlates> (its `forever/` build;
  nameplate-focused)
- **BetterBlizzFrames** - <https://github.com/Bodify/BetterBlizzFrames> (same author as
  BetterBlizzPlates, unit-frame-focused)
- **muleyoUI** - <https://github.com/muleyo/muleyoUI>
- **mini-auras** - <https://github.com/Verubato/mini-auras>

Confirmed precedent: weapon imbues looked unreachable through every stock-equivalent API
(`GetWeaponEnchantInfo()`, `C_PaperDollInfo.GetTemporaryEnchantmentInfo`, `C_UnitAuras`
enumeration) until EllesmereUI's source showed the real answer was a WoW-Forever-specific enum
(`Enum.ItemEnchantType.Imbue`) read through a different API (`C_Item.GetWeaponEnchantInfo`).

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

4. **Review `CURSEFORGE_DESCRIPTION.md`**: this file (gitignored, local only) is the CurseForge
   project description page. Check whether any changes since the last review add a feature,
   option, or behavior that a CurseForge visitor would care about, and if so update the relevant
   bullet or add a new one. Phrase additions the same way as the rest of the file: plain,
   non-technical, user-facing language - no mention of internal module/file names, commit
   messages, or implementation details. Skip purely internal changes (refactors, bug fixes that
   just restore intended behavior, dev tooling). Show the user the diff and get confirmation, then
   remind them to paste the updated text into the CurseForge project page manually (it isn't
   uploaded by the pipeline).

5. **Commit**: commit message `Release <version>`, containing the `.toc` and `CHANGELOG.md`
   changes.

6. **Tag**: create an annotated git tag exactly matching the version number, **without a "v"
   prefix** (e.g. `0.2.0`) - this tag is passed 1:1 as `project-version` to the CurseForge
   pipeline (BigWigsMods/packager).

7. **Mandatory checklist before every push**: never push without checking this first:
   - Has the version in `SmuveUI.toc` actually been bumped since the last tag? If not, do that
     first (step 2) - never push with an unchanged version.
   - Show the user the new `CHANGELOG.md` section and wait for their explicit confirmation
     (review) before proceeding.
   - Only then: `git push && git push --tags`. This automatically triggers the CurseForge upload
     via the GitHub Action (trigger: tags only, not regular pushes to `main`).

`.pkgmeta` uses `manual-changelog`, meaning the packager uploads the exact content of
`CHANGELOG.md` to CurseForge instead of generating one from the git log automatically - step 3 is
therefore important for a clean changelog on CurseForge.
