/* OpenMinis composer popup — reliable entry on Firefox Android (toolbar icon).
 * Pre-fills the current tab's URL and any clipboard text so the user can
 * review/edit then send, regardless of whether context-menu long-press works.
 */
"use strict";

const urlInput = document.getElementById("url");
const textInput = document.getElementById("text");
const sendBtn = document.getElementById("send");
const stat = document.getElementById("stat");

function setStat(msg, cls) {
  stat.textContent = msg;
  stat.className = cls || "";
}

async function prefetch() {
  // Current active tab's title + url (activeTab granted after opening popup).
  try {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (tab && tab.url && !/^about:|^moz-extension:/.test(tab.url)) {
      urlInput.value = tab.url;
      if (!textInput.value.trim()) textInput.value = tab.title || "";
    }
  } catch (_) { /* tabs API unavailable when not on a normal page */ }

  // Clipboard text, if present.
  try {
    const clip = await navigator.clipboard.readText();
    if (clip && clip.trim()) textInput.value = clip.trim();
  } catch (_) { /* clipboard read not permitted */ }
}

sendBtn.addEventListener("click", async () => {
  const url = urlInput.value.trim();
  const text = textInput.value.trim();
  if (!url && !text) {
    setStat("请填写 URL 或文字", "err");
    return;
  }
  sendBtn.disabled = true;
  setStat("发送中…");
  const result = await OpenMinisApi.share({ url, text, title: "", source: "Firefox" });
  sendBtn.disabled = false;
  if (result.ok) {
    setStat("✓ 已发送", "ok");
    setTimeout(() => window.close(), 700);
  } else if (result.message === "NO_SERVER") {
    setStat("未配置接收端，请在设置中填写地址", "err");
    browser.runtime.openOptionsPage();
  } else {
    setStat("✗ 发送失败：" + result.message, "err");
  }
});

prefetch();
