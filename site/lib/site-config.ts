export const siteConfig = {
  githubRepo:
    process.env.NEXT_PUBLIC_GITHUB_REPO ?? "https://github.com/chasemcdo/speak",
  latestDmgUrl:
    process.env.NEXT_PUBLIC_LATEST_DMG_URL ??
    "https://github.com/chasemcdo/speak/releases/latest/download/Speak.dmg",
  releasesUrl:
    process.env.NEXT_PUBLIC_RELEASES_URL ??
    "https://github.com/chasemcdo/speak/releases",
  docsBaseUrl: process.env.NEXT_PUBLIC_DOCS_BASE_URL ?? "https://speak.app",
};
