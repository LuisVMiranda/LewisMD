// Strip YAML or TOML frontmatter from markdown content.
// Returns the remaining content plus the number of stripped source lines
// so preview/outline consumers can keep line-based sync accurate.

export function stripMarkdownFrontmatter(content) {
  if (!content) return { content, frontmatterLines: 0 }

  // YAML frontmatter: --- ... ---
  if (content.startsWith("---")) {
    const endMatch = content.indexOf("\n---", 3)
    if (endMatch !== -1) {
      const afterFrontmatter = content.indexOf("\n", endMatch + 4)
      if (afterFrontmatter !== -1) {
        const frontmatter = content.slice(0, afterFrontmatter + 1)
        return {
          content: content.slice(afterFrontmatter + 1).trimStart(),
          frontmatterLines: frontmatter.split("\n").length
        }
      }

      return {
        content: "",
        frontmatterLines: content.split("\n").length
      }
    }
  }

  // TOML frontmatter: +++ ... +++
  if (content.startsWith("+++")) {
    const endMatch = content.indexOf("\n+++", 3)
    if (endMatch !== -1) {
      const afterFrontmatter = content.indexOf("\n", endMatch + 4)
      if (afterFrontmatter !== -1) {
        const frontmatter = content.slice(0, afterFrontmatter + 1)
        return {
          content: content.slice(afterFrontmatter + 1).trimStart(),
          frontmatterLines: frontmatter.split("\n").length
        }
      }

      return {
        content: "",
        frontmatterLines: content.split("\n").length
      }
    }
  }

  return { content, frontmatterLines: 0 }
}
