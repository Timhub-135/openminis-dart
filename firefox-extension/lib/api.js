/* OpenMinis extension API wrapper.
 * Talks to the LAN share receiver (share_receiver.py) over plain JSON HTTP.
 * The receiver URL is stored in browser.storage.local under key "serverUrl".
 */
"use strict";

const OpenMinisApi = {
  storageKey: "serverUrl",

  async getServerUrl() {
    const data = await browser.storage.local.get(this.storageKey);
    return data[this.storageKey] || "";
  },

  async setServerUrl(url) {
    await browser.storage.local.set({ [this.storageKey]: url });
  },

  /**
   * Try to reach the receiver and POST a share.
   * @returns {Promise<{ok:boolean, message:string}>}
   */
  async share(payload) {
    const base = await this.getServerUrl();
    if (!base) {
      return { ok: false, message: "NO_SERVER" }; // caller may open options
    }
    const url = base.replace(/\/+$/, "") + "/share";
    try {
      const resp = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (resp.ok) {
        return { ok: true, message: await resp.text() };
      }
      return { ok: false, message: "HTTP " + resp.status };
    } catch (e) {
      return { ok: false, message: String(e) };
    }
  },

  /** Health probe for the options page "test connection". */
  async health() {
    const base = await this.getServerUrl();
    if (!base) return { ok: false };
    try {
      const resp = await fetch(base.replace(/\/+$/, "") + "/health");
      return { ok: resp.ok, status: resp.status };
    } catch (e) {
      return { ok: false, error: String(e) };
    }
  },
};
