// Element policy applied on top of DOMPurify in the live reader.
// Pure so it can be unit-tested with any DOM.

/**
 * Inputs are only allowed as the renderer's own disabled task checkboxes.
 * Anything else (text fields, buttons rendered as inputs, ...) is removed.
 * Returns true when the element should be kept; may normalise it in place.
 */
export function enforceInputPolicy(element) {
  if (!element || element.nodeName?.toLowerCase() !== 'input') return true;
  const isTaskCheckbox = (element.getAttribute('type') || '').toLowerCase() === 'checkbox'
    && (element.getAttribute('class') || '').split(/\s+/).includes('task-checkbox');
  if (!isTaskCheckbox) return false;
  // Even a forged task checkbox in raw HTML stays inert.
  element.setAttribute('disabled', '');
  for (const name of ['name', 'value', 'form', 'formaction', 'onclick', 'onchange']) element.removeAttribute(name);
  return true;
}
