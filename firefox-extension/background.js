/* OpenMinis Firefox extension — sender.
 *
 * Entry points on Firefox Android:
 *   1. context menu ("发送到 OpenMinis") on link / page / selection via long-press.
 *   2. toolbar (browser_action) → composer popup: pre-fills current page URL +
 *      any clipboard text, editable, then POSTs to the OpenMinis receiver.
 *
 * Uses browser.menus (contextMenus alias). Config: serverUrl in storage.local.
 */
"use strict";

const MENU_ID = "openminis-share";

// MV2 keeps a persistent background, which loads exactly once — a top-level
// create() is the documented reliable approach (matches MDN guidance for
// persistent background pages).
function createMenu() {
  try {
    browser.menus.create({
      id: MENU_ID,
      title: "发送到 OpenMinis",
      contexts: ["selection", "link", "page"],
    });
    console.log("[openminis-share] menu created");
  } catch (e) {
    // If it already exists (e.g. reload), remove then retry once.
    try {
      browser.menus.remove(MENU_ID);
      browser.menus.create({
        id: MENU_ID,
        title: "发送到 OpenMinis",
        contexts: ["selection", "link", "page"],
      });
    } catch (e2) {
      console.error("[openminis-share] create menu failed:", e2);
    }
  }
}

createMenu();

browser.menus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== MENU_ID) return;

  const url = info.linkUrl || (tab && tab.url) || "";
  const text = info.selectionText || "";
  const title = (tab && tab.title) || "";
  const effectiveUrl = (!info.linkUrl && text && tab && tab.url) ? tab.url : url;

  const payload = { url: effectiveUrl, text, title: title.trim(), source: "Firefox" };
  const result = await OpenMinisApi.share(payload);
  if (!result.ok && result.message === "NO_SERVER") {
    browser.runtime.openOptionsPage();
  }
});
