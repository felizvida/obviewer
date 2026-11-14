# Hostile HTML (security check)

Every line below should render as harmless content. Nothing may run, load from the network, or navigate.

<script>document.body.innerHTML = 'SCRIPT RAN'</script>

<img src="x" onerror="document.body.innerHTML = 'ONERROR RAN'">

<iframe src="https://example.com"></iframe>

<a href="javascript:document.body.innerHTML='JS LINK RAN'">javascript: link (should do nothing)</a>

<a href="file:///etc/hosts">file: link (should do nothing)</a>

<img src="https://example.com/tracker.png" alt="remote image (should not load)">

<form action="https://example.com"><input name="q"><button>Submit</button></form>

<svg><script>document.body.innerHTML = 'SVG SCRIPT RAN'</script></svg>

<object data="https://example.com/x.swf"></object>

<style>body { display: none }</style>

<div style="background:url(https://example.com/bg.png)">inline style with a remote background (should not load)</div>

[Markdown javascript link](javascript:alert(1)) and ![remote markdown image](https://example.com/x.png)

<details><summary>Details still works</summary>Safe content.</details>
