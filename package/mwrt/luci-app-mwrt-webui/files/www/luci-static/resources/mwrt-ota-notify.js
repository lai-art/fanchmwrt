/* mwrt-ota-notify.js —— 有新固件时在页面顶部给一条可关闭的提示
 *
 * 只读 rpcd luci.mwrt-ota latest(读缓存, 不联网); 缓存由每天一次的 cron 写入。
 * 只提示, 从不自动下载或刷写。关掉之后同一版本不再提示(localStorage 记版本号)。
 * 在线更新页本身不显示。由全局 footer.ut 注入, 所有主题都有, 样式自带。 */
(function () {
	'use strict';

	if (window.__mwrtOtaNotify) return;
	window.__mwrtOtaNotify = true;

	var me = document.currentScript;
	var PAGE = (me && me.getAttribute('data-page')) || '';
	var KEY = 'mwrt-ota-dismissed';

	if (/\/admin\/system\/ota\/?$/.test(location.pathname)) return;

	function run() {
		if (!window.L || !L.require) return;
		L.require('rpc').then(function (rpc) {
			var latest = rpc.declare({ object: 'luci.mwrt-ota', method: 'latest' });
			return latest();
		}).then(function (r) {
			if (!r || !r.update || !r.version) return;
			var seen = '';
			try { seen = localStorage.getItem(KEY) || ''; } catch (e) {}
			if (seen === r.version) return;
			show(r.version);
		}).catch(function () { /* 没权限或没装后端: 不提示 */ });
	}

	function show(version) {
		if (document.getElementById('mwrt-ota-banner')) return;

		var bar = document.createElement('div');
		bar.id = 'mwrt-ota-banner';
		bar.setAttribute('role', 'status');
		bar.setAttribute('style',
			'position:fixed;left:50%;top:12px;transform:translateX(-50%);z-index:2147483000;' +
			'display:flex;align-items:center;gap:12px;max-width:92vw;box-sizing:border-box;' +
			'padding:10px 14px 10px 18px;border-radius:10px;font-size:14px;line-height:1.4;' +
			'background:#1e88e5;color:#fff;box-shadow:0 4px 18px rgba(0,0,0,.25)');

		var text = document.createElement('span');
		text.textContent = '发现新固件 v' + version;

		var go = document.createElement('a');
		go.id = 'mwrt-ota-banner-go';
		go.href = PAGE;
		go.textContent = '前往更新';
		go.setAttribute('style', 'color:#fff;font-weight:600;text-decoration:underline;white-space:nowrap');

		var x = document.createElement('button');
		x.type = 'button';
		x.id = 'mwrt-ota-banner-close';
		x.textContent = '×';
		x.setAttribute('aria-label', '关闭提示');
		x.setAttribute('style', 'background:none;border:0;color:#fff;font-size:20px;line-height:1;cursor:pointer;padding:0 4px;opacity:.85');
		x.addEventListener('click', function () {
			try { localStorage.setItem(KEY, version); } catch (e) {}
			bar.remove();
		});

		bar.appendChild(text);
		bar.appendChild(go);
		bar.appendChild(x);
		document.body.appendChild(bar);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', run);
	else
		run();
}());
