/* OpenMinis options page logic. */
"use strict";

const input = document.getElementById("serverUrl");
const status = document.getElementById("status");

function showStatus(msg, cls) {
  status.textContent = msg;
  status.className = cls || "";
}

async function init() {
  const url = await OpenMinisApi.getServerUrl();
  if (url) input.value = url;
}

document.getElementById("save").addEventListener("click", async () => {
  let url = input.value.trim();
  if (url && !/^https?:\/\//i.test(url)) {
    url = "http://" + url;
  }
  await OpenMinisApi.setServerUrl(url);
  showStatus(url ? "已保存： " + url : "已清除，请填写地址后再保存", "ok");
});

document.getElementById("test").addEventListener("click", async () => {
  let url = input.value.trim();
  if (url && !/^https?:\/\//i.test(url)) {
    url = "http://" + url;
    input.value = url;
  }
  await OpenMinisApi.setServerUrl(url); // test uses current value
  const r = await OpenMinisApi.health();
  if (r.ok) {
    showStatus("✓ 连接成功，收到接收端响应", "ok");
  } else {
    showStatus("✗ 连接失败：" + (r.error || ("HTTP " + r.status)), "err");
  }
});

init();
