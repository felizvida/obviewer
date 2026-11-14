// Task list items ("- [ ] todo", "- [x] done", Obsidian custom statuses like
// "- [/] in progress") and heading anchors.

import { uniqueSlug } from '../util.js';

const TASK = /^\[([ xX/\-><!?*"lbiSIpcfkwud])\][ \t]+/;

export function taskListPlugin(md) {
  md.core.ruler.after('inline', 'ob_tasks', (state) => {
    const tokens = state.tokens;
    for (let i = 2; i < tokens.length; i += 1) {
      const inline = tokens[i];
      if (inline.type !== 'inline') continue;
      if (tokens[i - 1].type !== 'paragraph_open' || tokens[i - 2].type !== 'list_item_open') continue;
      const first = inline.children?.[0];
      if (!first || first.type !== 'text') continue;
      const match = TASK.exec(first.content);
      if (!match) continue;

      const status = match[1];
      const checked = status !== ' ';
      first.content = first.content.slice(match[0].length);
      const box = new state.Token('html_inline', '', 0);
      box.content = `<input class="task-checkbox" type="checkbox" disabled${checked ? ' checked' : ''} aria-label="${checked ? 'Completed task' : 'Open task'}">`;
      inline.children.unshift(box);

      const item = tokens[i - 2];
      item.attrJoin('class', 'task-list-item');
      if (status !== ' ' && status.toLowerCase() !== 'x') item.attrSet('data-task', status);
      if (checked) item.attrJoin('class', 'is-checked');
      for (let j = i - 3; j >= 0; j -= 1) {
        const candidate = tokens[j];
        if ((candidate.type === 'bullet_list_open' || candidate.type === 'ordered_list_open') && candidate.level === item.level - 1) {
          if (!(candidate.attrGet('class') || '').includes('contains-task-list')) candidate.attrJoin('class', 'contains-task-list');
          break;
        }
      }
    }
  });
}

export function headingAnchorPlugin(md) {
  md.core.ruler.push('ob_heading_ids', (state) => {
    const env = state.env;
    const registry = env.slugRegistry ?? (env.slugRegistry = new Map());
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i += 1) {
      const open = tokens[i];
      if (open.type !== 'heading_open') continue;
      const inline = tokens[i + 1];
      const text = (inline.children ?? [])
        .filter((child) => child.type === 'text' || child.type === 'code_inline' || child.type === 'ob_wikilink')
        .map((child) => (child.type === 'ob_wikilink' ? (child.meta?.alias || child.meta?.note || '') : child.content))
        .join('')
        .trim();
      const id = uniqueSlug(env.idPrefix ? `${env.idPrefix}-${text}` : text, registry);
      open.attrSet('id', id);
      open.attrSet('data-heading', text);
      if (env.headings && open.level === 0) {
        env.headings.push({ level: Number(open.tag.slice(1)), text, id });
      }
    }
  });
}
