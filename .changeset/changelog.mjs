// Changelog lines without commit hashes, since players read them on CurseForge.
export default {
  getReleaseLine: async ({ summary }) => `- ${summary.trim().replace(/\n/g, '\n  ')}`,
  getDependencyReleaseLine: async () => '',
};
