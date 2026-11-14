import test from 'node:test';
import assert from 'node:assert/strict';
import { enforceInputPolicy } from '../src/core/sanitize-policy.js';
import { dom } from './helpers.js';

test('only disabled task checkboxes survive', () => {
  const root = dom('<input name="q"><input type="checkbox" name="x"><input class="task-checkbox" type="checkbox" name="n" onclick="x()"><p>keep</p>');
  const [text, plainBox, taskBox] = root.querySelectorAll('input');
  assert.equal(enforceInputPolicy(text), false);
  assert.equal(enforceInputPolicy(plainBox), false);
  assert.equal(enforceInputPolicy(taskBox), true);
  assert.ok(taskBox.hasAttribute('disabled'));
  assert.equal(taskBox.getAttribute('name'), null);
  assert.equal(taskBox.getAttribute('onclick'), null);
  assert.equal(enforceInputPolicy(root.querySelector('p')), true);
});
