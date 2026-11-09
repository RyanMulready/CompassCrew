# Changesets

Each change that players should hear about gets a changeset: run `npx changeset`, or add a file here like

```md
---
"compasscrew": patch
---

Fix the "members elsewhere" row overlapping the distance readout.
```

Use `patch` for fixes, `minor` for new features, `major` for breaking changes. The text becomes the changelog line on CurseForge and GitHub.

Merging to `main` opens or updates a "Version Packages" PR. Merging that PR tags the release and publishes it to CurseForge.
