/* mwrt-phone.js v3 (s103)
 * s103:短信功能(IMS)未开启(phone_state 的 ims 严格等于 0;-1 / 缺失不提示)时:拨号盘顶部出琥珀色提示条 + 「去开启」
 *   (直达短信管理设置页,地址由 data-sms 派生),「拨出」键禁用(aria-disabled,数字键仍可输入);首页拨号按钮(.ph-btn)
 *   由本脚本运行时加 / 去 ph-ims-off 类(小琥珀圆点 + title / aria-label 写明原因)。ims 回到 1 后全部自动恢复;通话中 / 来电中不受影响。
 * 5700 模组:拨号悬浮框 + 全屏来电 + 新短信 / 未接来电提醒。
 * s102:新短信和未接来电不再自己弹左上角 toast,改并入右上角全局通知中心(mwrt-notice.js,
 *   数据来自 rpcd luci.mwrt-notice);这里只负责「发现新事件 → 调 window.mwrtNotice.refresh()」让卡片 3 秒内出现。
 *   window.mwrtNotice 不存在(通知中心脚本没加载)时才退回原来的 toast,两处绝不同时出现。
 *   拨号盘的操作反馈(挂断失败 / 拨号不可用)不是通知,仍用 toast。全屏来电界面不变。
 * 单文件,CSS 自带注入,不依赖 argon / .P / FontAwesome,不使用 ws,只走同源 XHR。
 * 对外:window.MwrtPhone = { open(), close(), version, state() }
 * 接口(admin/modem 下):phone_state(GET) / phone_dial / phone_answer / phone_hangup(POST+token)
 * 注意:不写 prefers-reduced-motion 规则,响铃动画始终播放。 */
(function () {
	'use strict';
	if (window.top !== window.self) return;
	if (window.__mwrtPhone) return;
	window.__mwrtPhone = 1;

	var VERSION = '3';
	var TAG = document.currentScript || (function () {
		var s = document.getElementsByTagName('script'), i;
		for (i = s.length - 1; i >= 0; i--) if (/mwrt-phone\.js/.test(s[i].src || '')) return s[i];
		return null;
	})();
	var BASE = ((TAG && TAG.getAttribute('data-base')) || '/cgi-bin/luci/admin/modem').replace(/\/+$/, '');
	var SMS_URL = (TAG && TAG.getAttribute('data-sms')) || '';
	/* s103:短信管理设置页 = data-sms 地址 + ?view=settings(已带查询串时用 &) */
	var SMS_SET_URL = SMS_URL ? SMS_URL + (SMS_URL.indexOf('?') < 0 ? '?' : '&') + 'view=settings' : '';
	var IMS_MSG = '短信功能(IMS)未开启:无法拨打和接听电话,也收不到短信。';
	var IMS_BTN_TIP = '短信功能(IMS)未开启,暂时无法拨打';

	var Z_CAP = 2147483210, Z_DLG = 2147483220, Z_TOAST = 2147483250, Z_IN = 2147483300;
	var K_LEAD = 'mwrt-phone-lead', K_LAST = 'mwrt-phone-last', K_AGREE = 'mwrt-phone-agree',
		K_SNAP = 'mwrt-phone-snap', K_POKE = 'mwrt-phone-poke';
	var WARN = '当前设备没有音频支持,只能用于测试通话功能,请勿用于非法途径,引起后果,用户需要承担此功能全部责任。拨出的电话仍会真实产生呼叫,可能产生话费。';
	var EMERG = ['110', '112', '119', '120', '122', '911', '999', '000'];

	/* ===================== 小工具 ===================== */
	var NS = 'http://www.w3.org/2000/svg';
	var PATHS = {
		phone: 'M6.6 10.8c1.4 2.8 3.8 5.1 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1C10.6 21 3 13.4 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1L6.6 10.8z',
		back: 'M22 3H7c-.7 0-1.2.4-1.6.9L0 12l5.4 8.1c.4.5.9.9 1.6.9h15c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-3 12.6L17.6 17 14 13.4 10.4 17 9 15.6 12.6 12 9 8.4 10.4 7 14 10.6 17.6 7 19 8.4 15.4 12 19 15.6z',
		close: 'M19 6.4 17.6 5 12 10.6 6.4 5 5 6.4 10.6 12 5 17.6 6.4 19 12 13.4 17.6 19 19 17.6 13.4 12z',
		msg: 'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-2 12H6v-2h12v2zm0-3H6V9h12v2zm0-3H6V6h12v2z',
		user: 'M12 12c2.2 0 4-1.8 4-4s-1.8-4-4-4-4 1.8-4 4 1.8 4 4 4zm0 2c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4z',
		info: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z'
	};
	function icon(n, sz) {
		var s = document.createElementNS(NS, 'svg'), p = document.createElementNS(NS, 'path');
		s.setAttribute('viewBox', '0 0 24 24');
		s.setAttribute('width', sz || 24); s.setAttribute('height', sz || 24);
		s.setAttribute('aria-hidden', 'true'); s.setAttribute('focusable', 'false');
		p.setAttribute('d', PATHS[n]); p.setAttribute('fill', 'currentColor');
		s.appendChild(p);
		return s;
	}
	function h(tag, cls, text) {
		var e = document.createElement(tag);
		if (cls) e.className = cls;
		if (text != null) e.textContent = text;
		return e;
	}
	function btn(cls, label) {
		var b = h('button', cls);
		b.type = 'button';
		if (label) b.setAttribute('aria-label', label);
		return b;
	}
	function setText(e, v) { if (e && e.textContent !== v) e.textContent = v; }
	function setCls(e, c, on) { if (e && e.classList.contains(c) !== !!on) e.classList.toggle(c, !!on); }
	function setAttr(e, k, v) { if (e && e.getAttribute(k) !== v) e.setAttribute(k, v); }
	function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
	function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* 忽略 */ } }
	function lsDel(k) { try { localStorage.removeItem(k); } catch (e) { /* 忽略 */ } }
	function jparse(s) { try { return s ? JSON.parse(s) : null; } catch (e) { return null; } }
	function pad2(n) { return (n < 10 ? '0' : '') + n; }
	function fmtDur(sec) {
		sec = Math.max(0, Math.floor(sec || 0));
		var m = Math.floor(sec / 60), s = sec % 60;
		return m >= 60 ? Math.floor(m / 60) + ':' + pad2(m % 60) + ':' + pad2(s) : pad2(m) + ':' + pad2(s);
	}
	function fmtAgo(age) {
		age = Math.max(0, age || 0);
		if (age < 30) return '刚刚';
		if (age < 60) return Math.floor(age) + ' 秒前';
		if (age < 3600) return Math.floor(age / 60) + ' 分钟前';
		return Math.floor(age / 3600) + ' 小时前';
	}
	/* 仅显示用的号码分组 */
	function fmtNum(n) {
		if (!n) return '';
		var plus = n.charAt(0) === '+', d = n.replace(/\D/g, '');
		if (plus && d.indexOf('86') === 0 && d.length === 13) return '+86 ' + d.slice(2, 5) + ' ' + d.slice(5, 9) + ' ' + d.slice(9);
		var out = d, cc = '';
		/* 带 +86 的输入过程中也按国内手机分组,避免 +861 3800 这种错位 */
		if (plus && d.indexOf('86') === 0 && d.length > 5) { cc = '+86 '; d = d.slice(2); out = d; plus = false; }
		/* 6 位及以下(如 10086、95588)不分组,与手机一致 */
		if (d.length > 7) out = d.slice(0, 3) + ' ' + d.slice(3, 7) + ' ' + d.slice(7);
		else if (d.length === 7) out = d.slice(0, 3) + ' ' + d.slice(3);
		return cc + (plus ? '+' : '') + out;
	}
	function isEmerg(n) {
		var plus = n.charAt(0) === '+', d = n.replace(/\D/g, ''), i, e, diff;
		for (i = 0; i < EMERG.length; i++) {
			e = EMERG[i];
			if (!plus && d === e) return true;
			if (plus) {
				diff = d.length - e.length;
				if (diff >= 1 && diff <= 3 && d.slice(-e.length) === e) return true;
			}
		}
		return false;
	}
	function validNum(n) { return /^\+?[0-9]{3,20}$/.test(n); }

	/* ===================== XHR ===================== */
	function token() {
		if (window.L && L.env && L.env.token) return L.env.token;
		var i = document.querySelector('input[name="token"]');
		return i ? i.value : '';
	}
	function req(method, url, body, cb, timeout) {
		var x = new XMLHttpRequest();
		x.open(method, method === 'GET' ? url + (url.indexOf('?') < 0 ? '?' : '&') + '_=' + Date.now() : url, true);
		x.timeout = timeout || 15000;
		if (body !== null) x.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
		x.onreadystatechange = function () {
			if (x.readyState !== 4) return;
			var d = null;
			try { d = JSON.parse(x.responseText); } catch (e) { d = null; }
			cb(d && typeof d === 'object' ? d : null, x.status);
		};
		x.send(body);
	}
	function form(o) {
		var b = [], k;
		for (k in o) b.push(encodeURIComponent(k) + '=' + encodeURIComponent(o[k]));
		return b.join('&');
	}

	/* ===================== 状态 ===================== */
	var ID = Math.random().toString(36).slice(2, 10);
	var snap = null;                 /* {data, events, recvAt} */
	var dead = false, supported = null, gotFirst = false;
	var host = null, els = {};
	var dlgOpen = false, prevFocus = null;
	var numStr = '', dialErr = '', dialNote = '';
	var busy = { dial: false, ans: false, hang: false };
	var pendingDial = null;          /* {number,t,prevKey} */
	var coolUntil = 0;
	var hidKey = {};                 /* 本地挂断的通话 -> 时刻 */
	var endSeen = {};
	var answerAt = 0, answerKey = '', ovNote = '';
	var endTimer = 0, tickTimer = 0, coolTimer = 0, hidTimer = 0;
	var lastView = '';
	/* 轮询 */
	var isLeader = false, pollTimer = 0, polling = false, again = false, failN = 0;
	var genMem = '', sinceMem = 0, haveBase = false, unsupRetry = 0, unsupDone = false;
	/* 短信 / 未接来电 toast */
	var pendingEv = [], pendingIds = {};
	var tQueue = [], tShown = [];
	var bc = null;

	/* ===================== CSS ===================== */
	function css() {
		var F = '-apple-system,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei UI","Noto Sans SC",sans-serif';
		var R = '#mwrt-ph ';
		var BR = 'appearance:none !important;-webkit-appearance:none !important;border:0 !important;box-shadow:none !important;min-height:0 !important;margin:0;padding:0;font:inherit;text-shadow:none !important;text-transform:none !important;letter-spacing:normal;cursor:pointer;-webkit-tap-highlight-color:transparent;outline:0;';
		return [
			R + ',' + R + '*{box-sizing:border-box}',
			'#mwrt-ph{font-family:' + F + ';font-size:14px;line-height:1.4;color:var(--tx);--grn:#2fc95a;--red:#ff3b30}',
			'#mwrt-ph.dk{--tx:#f5f7fb;--sub:rgba(235,240,250,.6);--rtx:#ff6b60;--bg:rgba(30,33,43,.82);--solid:#1d202b;--key:rgba(255,255,255,.12);--keyh:rgba(255,255,255,.22);--line:rgba(255,255,255,.1);--wbg:rgba(255,196,60,.15);--wbd:rgba(255,196,60,.38);--wtx:#ffd666;--shadow:0 26px 70px rgba(0,0,0,.6),inset 0 0 0 1px rgba(255,255,255,.08);--mask:rgba(5,8,16,.58);--ovbg:linear-gradient(165deg,#0a1020 0%,#14284a 54%,#0f4a52 100%);--card:rgba(36,40,52,.94)}',
			'#mwrt-ph.lt{--tx:#10151f;--sub:rgba(16,21,31,.68);--rtx:#d70015;--bg:rgba(248,249,252,.94);--solid:#f6f7fa;--key:rgba(16,24,40,.07);--keyh:rgba(16,24,40,.15);--line:rgba(16,24,40,.1);--wbg:#fff3d1;--wbd:#f0c24a;--wtx:#7a5200;--shadow:0 26px 64px rgba(20,30,60,.3),inset 0 0 0 1px rgba(255,255,255,.75);--mask:rgba(20,28,45,.34);--ovbg:linear-gradient(165deg,#eaf2ff 0%,#dbeafe 52%,#d2f4ec 100%);--card:rgba(255,255,255,.96)}',
			R + 'button{' + BR + 'background:none;color:inherit;border-radius:0;line-height:inherit}',
			R + 'button:focus-visible{outline:2px solid #4c9bff !important;outline-offset:2px}',
			/* 遮罩与对话框 */
			R + '.ph-mask{display:none;position:fixed;inset:0;z-index:' + Z_DLG + ';background:var(--mask);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px);overscroll-behavior:contain;touch-action:none}',
			R + '.ph-mask.open{display:block;animation:ph-fade .18s ease-out}',
			R + '.ph-wrap{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:16px}',
			R + '.ph-dlg{position:relative;width:360px;max-width:100%;max-height:100%;overflow:auto;overscroll-behavior:contain;border-radius:24px;background:var(--bg);box-shadow:var(--shadow);-webkit-backdrop-filter:blur(26px) saturate(170%);backdrop-filter:blur(26px) saturate(170%);color:var(--tx);animation:ph-pop .22s cubic-bezier(.2,.9,.3,1.1);touch-action:auto}',
			'@supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))){' + R + '.ph-dlg{background:var(--solid)}}',
			R + '.ph-hd{display:flex;align-items:center;justify-content:space-between;padding:9px 9px 1px 22px}',
			R + '.ph-ttl{font-size:16px;font-weight:700;display:flex;align-items:center;gap:8px}',
			R + '.ph-test{display:none;font-size:11px;font-weight:700;padding:2px 8px;border-radius:99px;background:var(--wbg);color:var(--wtx);border:1px solid var(--wbd) !important}',
			R + '.ph-test.on{display:inline-block}',
			R + 'button.ph-x{width:44px !important;height:44px !important;border-radius:50% !important;display:flex;align-items:center;justify-content:center;color:var(--sub);background:transparent !important}',
			R + 'button.ph-x:hover{background:var(--key) !important}',
			R + '.ph-warn{margin:4px 16px 0;padding:8px 12px;border-radius:12px;background:var(--wbg);border:1px solid var(--wbd);color:var(--wtx);font-size:11.5px;line-height:1.5;font-weight:500}',
			/* s103: 短信功能(IMS)未开启提示条(琥珀色,沿用 .ph-warn 的配色变量) */
			R + '.ph-ims{display:none;align-items:center;gap:10px;margin:8px 16px 0;padding:8px 10px 8px 12px;border-radius:12px;background:var(--wbg);border:1px solid var(--wbd);color:var(--wtx);font-size:12px;line-height:1.5;font-weight:600}',
			R + '.ph-ims.on{display:flex}',
			R + '.ph-ims-t{flex:1;min-width:0}',
			R + 'a.ph-ims-go{flex:none;display:inline-flex;align-items:center;padding:4px 12px;border-radius:99px;background:#b45309 !important;color:#fff !important;font-size:12px;font-weight:700;line-height:1.4;text-decoration:none !important;cursor:pointer;-webkit-tap-highlight-color:transparent}',
			R + 'a.ph-ims-go:hover{filter:brightness(1.07)}',
			R + 'a.ph-ims-go:focus-visible{outline:2px solid #4c9bff !important;outline-offset:2px}',
			R + 'button.ph-call[aria-disabled="true"]{background:var(--key) !important;color:var(--sub) !important;box-shadow:none !important;cursor:not-allowed;opacity:.55}',
			R + '.ph-v{display:none}',
			R + '.ph-dlg.v-pad .ph-vpad,' + R + '.ph-dlg.v-call .ph-vcall,' + R + '.ph-dlg.v-agree .ph-vagree{display:block}',
			R + '.ph-dlg.v-agree .ph-warn{display:none}',
			/* 号码区 */
			R + '.ph-disp{min-height:64px;padding:10px 20px 0;text-align:center;display:flex;align-items:center;justify-content:center;cursor:text}',
			R + '.ph-num{font-family:"SF Mono","Cascadia Mono","Roboto Mono",Consolas,"Liberation Mono",monospace;font-size:32px;font-weight:500;letter-spacing:.5px;white-space:nowrap;overflow:hidden;text-overflow:clip;max-width:100%;font-variant-numeric:tabular-nums}',
			R + '.ph-num.s2{font-size:26px}' + R + '.ph-num.s3{font-size:21px}',
			R + '.ph-num.ph-ph{font-family:inherit;font-size:16px;font-weight:400;color:var(--sub);letter-spacing:0}',
			R + '.ph-err{min-height:20px;padding:2px 22px 6px;text-align:center;font-size:12.5px;color:var(--rtx);font-weight:500}',
			/* 拨号盘 */
			R + '.ph-keys{display:grid;grid-template-columns:repeat(3,72px);gap:12px 20px;justify-content:center;padding:6px 0 4px}',
			R + 'button.ph-key{width:72px !important;height:72px !important;border-radius:50% !important;background:var(--key) !important;display:flex;flex-direction:column;align-items:center;justify-content:center;color:var(--tx);user-select:none;-webkit-user-select:none;-webkit-touch-callout:none;touch-action:manipulation;transition:background .12s,transform .08s}',
			R + 'button.ph-key:hover{background:var(--keyh) !important}',
			R + 'button.ph-key:active{background:var(--keyh) !important;transform:scale(.94)}',
			R + 'button.ph-key[aria-disabled="true"]{opacity:.32;cursor:not-allowed}',
			R + 'button.ph-key[aria-disabled="true"]:active{transform:none}',
			R + '.ph-d{font-size:28px;font-weight:400;line-height:1;font-variant-numeric:tabular-nums}',
			R + '.ph-l{font-size:9.5px;font-weight:700;letter-spacing:2px;margin-top:3px;color:var(--sub);height:11px;line-height:11px}',
			R + '.ph-acts{display:grid;grid-template-columns:repeat(3,72px);gap:0 20px;justify-content:center;padding:12px 0 24px;align-items:center}',
			R + 'button.ph-call,' + R + 'button.ph-hang,' + R + 'button.ph-ans{width:72px !important;height:72px !important;border-radius:50% !important;display:flex;align-items:center;justify-content:center;color:#fff !important;transition:transform .08s,filter .12s,opacity .12s}',
			R + 'button.ph-call{background:var(--grn) !important;grid-column:2;box-shadow:0 8px 22px rgba(47,201,90,.38) !important}',
			R + 'button.ph-hang{background:var(--red) !important;box-shadow:0 8px 22px rgba(255,59,48,.38) !important}',
			R + 'button.ph-ans{background:var(--grn) !important;box-shadow:0 8px 22px rgba(47,201,90,.4) !important}',
			R + 'button.ph-call:active,' + R + 'button.ph-hang:active,' + R + 'button.ph-ans:active{transform:scale(.93)}',
			R + 'button.ph-call:disabled{background:var(--key) !important;color:var(--sub) !important;box-shadow:none !important;cursor:not-allowed}',
			R + 'button.ph-hang svg,' + R + '.ph-ans-ic{transform:rotate(135deg)}',
			R + 'button.ph-call svg,' + R + 'button.ph-ans svg{transform:none}',
			R + 'button.ph-ans svg{animation:ph-shake 1.4s ease-in-out infinite}',
			R + 'button.ph-bk{grid-column:3;width:72px !important;height:48px !important;display:flex;align-items:center;justify-content:center;color:var(--sub);border-radius:24px !important;background:transparent !important;visibility:hidden;touch-action:manipulation}',
			R + 'button.ph-bk.on{visibility:visible}',
			R + 'button.ph-bk:hover{color:var(--tx)}',
			/* 通话视图 */
			R + '.ph-cv{display:flex;flex-direction:column;align-items:center;padding:22px 20px 26px;text-align:center}',
			R + '.ph-av{width:92px;height:92px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;background:linear-gradient(145deg,#5b8cff,#35c2b0);box-shadow:0 10px 30px rgba(53,194,176,.35)}',
			R + '.ph-cnum{margin-top:14px;font-family:"SF Mono","Cascadia Mono","Roboto Mono",Consolas,monospace;font-size:26px;font-weight:500;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
			R + '.ph-cst{margin-top:6px;font-size:15px;color:var(--sub)}',
			R + '.ph-ctm{margin-top:4px;font-size:22px;font-weight:600;font-variant-numeric:tabular-nums;min-height:30px}',
			R + '.ph-cnote{margin-top:6px;font-size:12.5px;color:var(--wtx);min-height:18px;line-height:1.5}',
			R + '.ph-cacts{margin-top:18px;display:flex;flex-direction:column;align-items:center;gap:8px}',
			R + '.ph-cap-l{font-size:12px;color:var(--sub)}',
			/* 同意页 */
			R + '.ph-ag{padding:6px 22px 24px}',
			R + '.ph-agt{margin:6px 0 10px;font-size:18px;font-weight:700;color:var(--wtx)}',
			R + '.ph-agb{padding:14px;border-radius:14px;background:var(--wbg);border:1px solid var(--wbd);color:var(--wtx);font-size:13.5px;line-height:1.7;font-weight:500}',
			R + '.ph-agc{display:flex;gap:10px;align-items:flex-start;margin:16px 0 14px;font-size:13.5px;cursor:pointer}',
			R + '.ph-agc input{width:20px;height:20px;margin:1px 0 0;flex:none;accent-color:#2fc95a}',
			R + 'button.ph-agok{display:block;width:100% !important;height:46px !important;border-radius:23px !important;background:#178a3a !important;color:#fff !important;font-weight:700;font-size:15px}',
			R + 'button.ph-agok:disabled{background:var(--key) !important;color:var(--sub) !important;cursor:not-allowed}',
			/* 胶囊 */
			R + '.ph-cap{position:fixed;right:12px;bottom:calc(var(--mwrt-nav-reserve,0px) + 12px);z-index:' + Z_CAP + ';display:none;align-items:center;gap:10px;padding:4px 4px 4px 14px;border-radius:99px;background:var(--card);-webkit-backdrop-filter:blur(20px) saturate(170%);backdrop-filter:blur(20px) saturate(170%);box-shadow:var(--shadow);color:var(--tx);cursor:pointer;animation:ph-pop .2s ease-out}',
			R + '.ph-cap.on{display:flex}',
			R + '.ph-cap-dot{width:9px;height:9px;border-radius:50%;background:var(--grn);animation:ph-blink 1.4s ease-in-out infinite}',
			R + '.ph-cap-t{font-size:13.5px;font-weight:600;font-variant-numeric:tabular-nums;white-space:nowrap}',
			R + '.ph-cap-tag{font-size:10.5px;color:var(--wtx)}',
			R + 'button.ph-cap-h{width:40px !important;height:40px !important;border-radius:50% !important;background:var(--red) !important;color:#fff !important;display:flex;align-items:center;justify-content:center}',
			R + 'button.ph-cap-h svg{transform:rotate(135deg)}',
			/* 全屏来电 */
			R + '.ph-in{display:none;position:fixed;inset:0;z-index:' + Z_IN + ';background:var(--ovbg);color:var(--tx);flex-direction:column;align-items:center;overflow:hidden;padding:0 20px;padding-top:env(safe-area-inset-top,0px);padding-bottom:calc(env(safe-area-inset-bottom,0px))}',
			R + '.ph-in.on{display:flex;animation:ph-fade .22s ease-out}',
			R + '.ph-in-top{margin-top:max(7vh,36px);display:flex;flex-direction:column;align-items:center;gap:6px;z-index:1}',
			R + '.ph-in-lb{font-size:14px;color:var(--sub);letter-spacing:2px}',
			R + '.ph-in-test{display:none;font-size:11px;font-weight:700;padding:2px 10px;border-radius:99px;background:var(--wbg);color:var(--wtx);border:1px solid var(--wbd)}',
			R + '.ph-in-test.on{display:inline-block}',
			R + '.ph-avw{position:relative;width:132px;height:132px;margin-top:max(6vh,28px);display:flex;align-items:center;justify-content:center;flex:none}',
			R + '.ph-rp{position:absolute;inset:0;border-radius:50%;border:2px solid rgba(80,200,170,.55);opacity:0;display:none}',
			R + '.ph-in.m-ring .ph-rp{display:block;animation:ph-rip 2.4s ease-out infinite}',
			R + '.ph-rp:nth-child(2){animation-delay:.8s !important}' + R + '.ph-rp:nth-child(3){animation-delay:1.6s !important}',
			R + '.ph-in .ph-av{width:112px;height:112px;position:relative;z-index:1}',
			R + '.ph-in-num{margin-top:26px;font-family:"SF Mono","Cascadia Mono","Roboto Mono",Consolas,monospace;font-size:34px;font-weight:500;text-align:center;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;z-index:1}',
			R + '.ph-in-sub{margin-top:8px;font-size:16px;color:var(--sub);z-index:1}',
			R + '.ph-in-tm{margin-top:4px;font-size:26px;font-weight:600;font-variant-numeric:tabular-nums;min-height:34px;z-index:1}',
			R + '.ph-in-note{margin-top:6px;font-size:13px;color:var(--wtx);min-height:20px;text-align:center;z-index:1}',
			R + '.ph-in-acts{margin-top:auto;display:flex;gap:56px;align-items:flex-start;justify-content:center;z-index:1;padding-bottom:20px}',
			R + '.ph-in-g{display:flex;flex-direction:column;align-items:center;gap:10px;font-size:13px;color:var(--sub)}',
			R + '.ph-in.m-call .ph-in-g.ga,' + R + '.ph-in.m-end .ph-in-g{display:none}',
			R + '.ph-in.m-end .ph-in-acts{visibility:hidden}',
			R + '.ph-in-fine{font-size:12px;color:var(--sub);text-align:center;max-width:340px;margin:0 0 max(4vh,22px);line-height:1.6;z-index:1}',
			/* toast */
			R + '.ph-toasts{position:fixed;z-index:' + Z_TOAST + ';top:12px;left:12px;width:340px;max-width:calc(100vw - 24px);display:flex;flex-direction:column;gap:10px;pointer-events:none}',
			R + '.ph-toast{pointer-events:auto;position:relative;display:flex;gap:12px;align-items:flex-start;padding:12px 40px 12px 12px;border-radius:16px;background:var(--card);color:var(--tx);box-shadow:var(--shadow);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);cursor:pointer;animation:ph-slide .26s cubic-bezier(.2,.9,.3,1.1)}',
			R + '.ph-toast.out{animation:ph-out .22s ease-in forwards}',
			R + '.ph-t-ic{flex:none;width:38px;height:38px;border-radius:11px;display:flex;align-items:center;justify-content:center;color:#fff;background:linear-gradient(145deg,#4c8dff,#35b8d6)}',
			R + '.ph-toast.miss .ph-t-ic{background:linear-gradient(145deg,#ff6a5c,#ff3b30)}',
			R + '.ph-toast.info .ph-t-ic{background:linear-gradient(145deg,#8a96ad,#6b7690)}',
			R + '.ph-t-bd{min-width:0;flex:1}',
			R + '.ph-t-hd{display:flex;justify-content:space-between;gap:8px;align-items:baseline}',
			R + '.ph-t-nm{font-weight:700;font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
			R + '.ph-t-tm{font-size:11.5px;color:var(--sub);flex:none}',
			R + '.ph-t-tx{margin-top:2px;font-size:13px;color:var(--sub);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;word-break:break-all}',
			R + '.ph-t-full{margin-top:4px;font-size:12px;color:var(--rtx);font-weight:600}',
			R + 'button.ph-t-x{position:absolute;top:2px;right:2px;width:36px !important;height:36px !important;border-radius:50% !important;display:flex;align-items:center;justify-content:center;color:var(--sub);background:transparent !important}',
			R + 'button.ph-t-x:hover{background:var(--key) !important}',
			R + '.ph-more{align-self:flex-start;pointer-events:none;font-size:12px;font-weight:600;padding:3px 10px;border-radius:99px;background:var(--card);color:var(--sub);box-shadow:var(--shadow);display:none}',
			R + '.ph-more.on{display:block}',
			/* 手机 */
			'@media (max-width:768px){',
			R + '.ph-wrap{left:var(--mwrt-ov-l,0px);top:var(--mwrt-ov-t,0px);right:var(--mwrt-ov-r,0px);bottom:calc(var(--mwrt-ov-b,0px) + var(--mwrt-nav-reserve,0px));position:absolute;align-items:flex-end;padding:8px}',
			R + '.ph-dlg{width:min(100%,420px);border-radius:24px}',
			R + '.ph-toasts{left:50%;transform:translateX(-50%);width:min(calc(100vw - 16px),420px)}',
			R + '.ph-in-acts{gap:64px}',
			'}',
			'@media (max-height:700px){',
			R + '.ph-hd{padding:3px 5px 0 20px}',
			R + '.ph-warn{margin:2px 14px 0;padding:6px 10px;font-size:11px;line-height:1.45}',
			R + '.ph-keys{grid-template-columns:repeat(3,54px);gap:7px 18px;padding:2px 0 2px}',
			R + 'button.ph-key{width:54px !important;height:54px !important}',
			R + '.ph-acts{grid-template-columns:repeat(3,54px);gap:0 18px;padding:8px 0 14px}',
			R + 'button.ph-call{width:58px !important;height:58px !important}',
			R + 'button.ph-bk{width:54px !important;height:40px !important}',
			R + '.ph-d{font-size:23px}' + R + '.ph-l{font-size:8.5px;margin-top:1px;height:9px;line-height:9px}',
			R + '.ph-disp{min-height:42px;padding-top:4px}',
			R + '.ph-num{font-size:27px}' + R + '.ph-num.s2{font-size:23px}' + R + '.ph-num.s3{font-size:19px}',
			R + '.ph-err{min-height:16px;font-size:12px}',
			R + '.ph-cv{padding:14px 20px 18px}' + R + '.ph-av{width:76px;height:76px}',
			'}',
			'@media (max-width:480px){' + R + '.ph-ttl{font-size:15px}}',
			'@keyframes ph-fade{from{opacity:0}to{opacity:1}}',
			'@keyframes ph-pop{from{opacity:0;transform:translateY(10px) scale(.96)}to{opacity:1;transform:none}}',
			'@keyframes ph-slide{from{opacity:0;transform:translateY(-14px) scale(.97)}to{opacity:1;transform:none}}',
			'@keyframes ph-out{to{opacity:0;transform:translateX(-18px) scale(.97)}}',
			'@keyframes ph-rip{0%{transform:scale(.72);opacity:.55}100%{transform:scale(2.15);opacity:0}}',
			'@keyframes ph-shake{0%,60%,100%{transform:rotate(0)}10%{transform:rotate(-16deg)}20%{transform:rotate(14deg)}30%{transform:rotate(-12deg)}40%{transform:rotate(10deg)}50%{transform:rotate(-6deg)}}',
			'@keyframes ph-blink{0%,100%{opacity:1}50%{opacity:.35}}'
		].join('\n');
	}

	/* ===================== 主题 ===================== */
	function isDark() {
		// s107: 优先读整站深浅 html[data-darkmode](mwrt-aurora-boot.js), 读不到再按旧办法
		var dm = document.documentElement.getAttribute('data-darkmode');
		if (dm === 'true') return true;
		if (dm === 'false') return false;
		var p = document.getElementById('P') || document.querySelector('.P');
		if (p) {
			var t = '';
			try { t = getComputedStyle(p).getPropertyValue('--t1').trim(); } catch (e) { t = ''; }
			if (t) return !p.classList.contains('L');
		}
		var els2 = [document.body, document.documentElement], i, c, m;
		for (i = 0; i < els2.length; i++) {
			if (!els2[i]) continue;
			c = getComputedStyle(els2[i]).backgroundColor;
			m = /rgba?\(\s*(\d+)[ ,]+(\d+)[ ,]+(\d+)(?:[ ,/]+([\d.]+))?/.exec(c || '');
			if (m && (m[4] === undefined || parseFloat(m[4]) > 0.05))
				return (0.299 * m[1] + 0.587 * m[2] + 0.114 * m[3]) < 110;
		}
		return false;
	}
	function setTheme() {
		if (!host) return;
		var d = isDark();
		setCls(host, 'dk', d); setCls(host, 'lt', !d);
	}

	function ensureHost() {
		if (host) return host;
		var st = document.createElement('style');
		st.id = 'mwrt-ph-css'; st.textContent = css();
		(document.head || document.documentElement).appendChild(st);
		host = h('div'); host.id = 'mwrt-ph';
		host.className = isDark() ? 'dk' : 'lt';
		document.body.appendChild(host);
		return host;
	}

	/* ===================== 通话视图推导 ===================== */
	function curSnap() { return snap && snap.data && snap.data.supported !== false ? snap : null; }
	function rawCall() {
		var s = curSnap();
		if (!s) return null;
		if (Date.now() - s.recvAt > 20000) return null;
		if (s.data.stale) return null;
		var c = s.data.call;
		if (!c || !c.state || c.state === 'idle') return null;
		c._k = (s.data.gen || '') + ':' + c.cid;
		return c;
	}
	function viewCall() {
		var c = rawCall(), now = Date.now(), k;
		if (!c) { hidKey = {}; return null; }
		k = c._k;
		if (hidKey[k] && now - hidKey[k] < 6000) return null;
		if (c.state === 'ended') {
			if (endSeen[k] === undefined) endSeen[k] = gotFirst ? now : -1;
			if (endSeen[k] < 0 || now - endSeen[k] >= 1200) return null;
			if (!endTimer) endTimer = setTimeout(function () { endTimer = 0; render(); }, Math.max(30, 1250 - (now - endSeen[k])));
		}
		return c;
	}
	function elapsed(c) {
		if (!c) return 0;
		if (c.state === 'active') return (c.dur || 0) + (Date.now() - snap.recvAt) / 1000;
		return c.dur || 0;
	}
	function ovModeOf(c) {
		if (!c || c.dir !== 'in' || c.silent) return '';
		if (c.state === 'ringing') return 'ring';
		if (c.state === 'ended') return 'end';
		return 'call';
	}
	function pendActive(c) {
		if (!pendingDial) return false;
		if (Date.now() - pendingDial.t > 15000) {
			pendingDial = null; dialErr = '未能确认呼叫状态,请稍后查看或重试';
			return false;
		}
		if (c && c._k !== pendingDial.prevKey && c.dir === 'out') { pendingDial = null; return false; }
		return true;
	}
	function statusText(c, pend) {
		if (!c) return pend ? '拨号中…' : '';
		switch (c.state) {
		case 'ringing': return '来电响铃';
		case 'dialing': return '拨号中…';
		case 'alerting': return '对方响铃中…';
		case 'active': return '通话中';
		case 'ended':
			if (c.reason === 'failed') return '呼叫失败';
			return c.answered ? '通话已结束' : (c.dir === 'in' ? '来电已取消' : '通话已结束');
		}
		return '';
	}

	/* ===================== 渲染 ===================== */
	var needTick = false;
	/* s103: 严格等于 0 才算「短信功能(IMS)未开启」;-1(未知)/ 缺失 / 无快照一律不提示 */
	function imsIsOff() {
		var s = curSnap();
		return !!(s && s.data && s.data.ims === 0);
	}
	/* s103: 首页拨号按钮(.ph-btn,在 modem_info.htm 里)运行时加 / 去警示类;CSS 自带注入,不依赖 modem_info.htm 的改动 */
	function syncHomeBtn(off) {
		var bs = document.querySelectorAll('.ph-btn');
		if (!bs.length) return;
		if (off && !document.getElementById('mwrt-ph-ims-css')) {
			var st = document.createElement('style');
			st.id = 'mwrt-ph-ims-css';
			st.textContent = '.ph-btn.ph-ims-off{position:relative !important;overflow:visible !important}' +
				'.ph-btn.ph-ims-off::after{content:"" !important;position:absolute !important;top:-2px !important;right:-2px !important;width:8px !important;height:8px !important;' +
				'border-radius:50% !important;background:#f59e0b !important;box-shadow:0 0 0 2px #fff !important;pointer-events:none !important;display:block !important}';
			(document.head || document.documentElement).appendChild(st);
		}
		Array.prototype.forEach.call(bs, function (b) {
			if (off) {
				if (b.getAttribute('data-ph-t0') === null) {
					b.setAttribute('data-ph-t0', b.getAttribute('title') || '');
					b.setAttribute('data-ph-a0', b.getAttribute('aria-label') || '');
				}
				setAttr(b, 'title', (b.getAttribute('data-ph-t0') || '拨号') + '(' + IMS_BTN_TIP + ')');
				setAttr(b, 'aria-label', (b.getAttribute('data-ph-a0') || '打开拨号') + ',' + IMS_BTN_TIP);
				setCls(b, 'ph-ims-off', true);
			} else if (b.getAttribute('data-ph-t0') !== null) {
				var t0 = b.getAttribute('data-ph-t0'), a0 = b.getAttribute('data-ph-a0');
				if (t0) b.setAttribute('title', t0); else b.removeAttribute('title');
				if (a0) b.setAttribute('aria-label', a0); else b.removeAttribute('aria-label');
				b.removeAttribute('data-ph-t0'); b.removeAttribute('data-ph-a0');
				setCls(b, 'ph-ims-off', false);
			}
		});
	}

	function render() {
		if (dead) return;
		syncHomeBtn(imsIsOff());
		var c = viewCall();
		var pend = pendActive(c);
		/* 上一通刚结束的 ended 不应盖住新的拨号等待 */
		if (pend && c && c.state === 'ended' && c._k === pendingDial.prevKey) c = null;
		var ovMode = ovModeOf(c);
		var inDlgCall = !!(c && !ovMode) || (pend && !c);
		var s = curSnap();
		var fake = !!(s && s.data.fake);
		var st = c ? c.state : 'idle';
		var wantCap = !!(c && !ovMode && (st === 'dialing' || st === 'alerting' || st === 'active') || (pend && !c)) && !(dlgOpen && inDlgCall);
		var wantIn = !!ovMode;

		if (dlgOpen || wantCap || wantIn) ensureHost();
		if (host) setTheme();
		if (wantCap) { buildCap(); }
		if (els.cap) {
			setCls(els.cap, 'on', wantCap);
			if (wantCap) {
				var capTxt = c && st === 'active' ? '通话中 ' + fmtDur(elapsed(c)) : (c ? statusText(c) : '拨号中…');
				setText(els.capT, capTxt);
				setCls(els.capTag, 'on', fake);
				els.capTag.style.display = fake ? '' : 'none';
			}
		}
		if (wantIn) { buildOv(); renderOv(c, ovMode, fake); }
		else if (els.ov) { setCls(els.ov, 'on', false); ovNote = ''; }
		if (dlgOpen) renderDlg(c, pend, inDlgCall, fake);
		if (!c && !pend) { answerAt = 0; }

		needTick = !!(c || pend || coolUntil > Date.now());
		if (needTick && !tickTimer) tickTimer = setInterval(render, 500);
		else if (!needTick && tickTimer) { clearInterval(tickTimer); tickTimer = 0; }
		if (hidTimer) { clearTimeout(hidTimer); hidTimer = 0; }
		var hk, soon = 0;
		for (hk in hidKey) if (Date.now() - hidKey[hk] < 6000) soon = Math.max(soon, 6050 - (Date.now() - hidKey[hk]));
		if (soon) hidTimer = setTimeout(function () { hidTimer = 0; render(); }, soon);
	}

	/* ===================== 胶囊 ===================== */
	function buildCap() {
		if (els.cap) return;
		ensureHost();
		var cap = h('div', 'ph-cap'), dot = h('span', 'ph-cap-dot'), t = h('span', 'ph-cap-t', '通话中 00:00'),
			tag = h('span', 'ph-cap-tag', '测试模式'), hg = btn('ph-cap-h', '挂断');
		hg.appendChild(icon('phone', 18));
		tag.style.display = 'none';
		cap.appendChild(dot); cap.appendChild(t); cap.appendChild(tag); cap.appendChild(hg);
		cap.setAttribute('role', 'button'); cap.setAttribute('tabindex', '0'); cap.setAttribute('aria-label', '返回通话界面');
		cap.addEventListener('click', function (e) {
			if (e.target.closest && e.target.closest('.ph-cap-h')) return;
			open();
		});
		cap.addEventListener('keydown', function (e) {
			if ((e.key === 'Enter' || e.key === ' ') && e.target === cap) { e.preventDefault(); open(); }
		});
		hg.addEventListener('click', function (e) { e.stopPropagation(); doHangup(); });
		host.appendChild(cap);
		els.cap = cap; els.capT = t; els.capTag = tag;
	}

	/* ===================== 全屏来电 ===================== */
	function buildOv() {
		if (els.ov) return;
		ensureHost();
		var o = h('div', 'ph-in'), top = h('div', 'ph-in-top'), avw = h('div', 'ph-avw'), av = h('div', 'ph-av'),
			acts = h('div', 'ph-in-acts'), ga = h('div', 'ph-in-g ga'), gh = h('div', 'ph-in-g gh'), i;
		o.setAttribute('role', 'alertdialog'); o.setAttribute('aria-modal', 'true');
		o.setAttribute('aria-live', 'assertive'); o.setAttribute('aria-label', '来电');
		els.inLb = h('div', 'ph-in-lb', '来电');
		els.inTest = h('div', 'ph-in-test', '测试模式');
		top.appendChild(els.inLb); top.appendChild(els.inTest);
		for (i = 0; i < 3; i++) avw.appendChild(h('span', 'ph-rp'));
		av.appendChild(icon('user', 56));
		avw.appendChild(av);
		els.inNum = h('div', 'ph-in-num', '');
		els.inSub = h('div', 'ph-in-sub', '');
		els.inTm = h('div', 'ph-in-tm', '');
		els.inNote = h('div', 'ph-in-note', '');
		els.inAns = btn('ph-ans', '接听'); els.inAns.appendChild(icon('phone', 32));
		els.inHang = btn('ph-hang', '挂断'); els.inHang.appendChild(icon('phone', 32));
		ga.appendChild(els.inAns); ga.appendChild(h('span', '', '接听'));
		gh.appendChild(els.inHang); gh.appendChild(h('span', '', '挂断'));
		acts.appendChild(gh); acts.appendChild(ga);
		o.appendChild(top); o.appendChild(avw); o.appendChild(els.inNum); o.appendChild(els.inSub);
		o.appendChild(els.inTm); o.appendChild(els.inNote); o.appendChild(acts);
		o.appendChild(h('div', 'ph-in-fine', '本设备无音频,接通后对方只能听到静音,通话可能产生费用'));
		els.inAns.addEventListener('click', doAnswer);
		els.inHang.addEventListener('click', doHangup);
		host.appendChild(o);
		els.ov = o;
	}
	function renderOv(c, mode, fake) {
		var wasOn = els.ov.classList.contains('on');
		setCls(els.ov, 'on', true);
		setCls(els.ov, 'm-ring', mode === 'ring');
		setCls(els.ov, 'm-call', mode === 'call');
		setCls(els.ov, 'm-end', mode === 'end');
		setCls(els.inTest, 'on', fake);
		setText(els.inNum, c.number ? fmtNum(c.number) : '未知号码');
		var tm = '', sub = '';
		if (mode === 'ring') { sub = '来电'; setText(els.inLb, '电话'); }
		else if (mode === 'call') {
			sub = c.state === 'active' ? '通话中' : '连接中…';
			tm = c.state === 'active' ? fmtDur(elapsed(c)) : '';
			setText(els.inLb, '电话');
		} else {
			sub = c.answered ? '通话已结束 · 时长 ' + fmtDur(c.dur) : '来电已取消';
			setText(els.inLb, '电话');
		}
		setText(els.inSub, sub);
		setText(els.inTm, tm);
		/* 接听后 10 秒仍未 active */
		var note = ovNote;
		if (!note && answerAt && answerKey === c._k && c.state !== 'active' && c.state !== 'ended' && Date.now() - answerAt > 10000)
			note = '模组尚未确认接通';
		setText(els.inNote, note);
		setAttr(els.inAns, 'aria-disabled', busy.ans ? 'true' : 'false');
		els.inAns.style.opacity = busy.ans ? '.6' : '';
		els.inHang.style.opacity = busy.hang ? '.6' : '';
		if (!wasOn) {
			prevFocusOv = document.activeElement;
			try { (mode === 'ring' ? els.inAns : els.inHang).focus(); } catch (e) { /* 忽略 */ }
		}
	}
	var prevFocusOv = null;
	function ovVisible() { return !!(els.ov && els.ov.classList.contains('on')); }

	/* ===================== 拨号框 ===================== */
	function buildDlg() {
		if (els.mask) return;
		ensureHost();
		var mask = h('div', 'ph-mask'), wrap = h('div', 'ph-wrap'), dlg = h('div', 'ph-dlg v-pad'),
			hd = h('div', 'ph-hd'), ttl = h('div', 'ph-ttl'), x = btn('ph-x', '关闭');
		dlg.setAttribute('role', 'dialog'); dlg.setAttribute('aria-modal', 'true'); dlg.setAttribute('aria-label', '拨号');
		ttl.appendChild(h('span', '', '拨号'));
		els.test = h('span', 'ph-test', '测试模式');
		ttl.appendChild(els.test);
		x.appendChild(icon('close', 20));
		hd.appendChild(ttl); hd.appendChild(x);
		dlg.appendChild(hd);
		dlg.appendChild(h('div', 'ph-warn', WARN));

		/* 同意页 */
		var ag = h('div', 'ph-v ph-vagree ph-ag'), cb = document.createElement('input'), lb = h('label', 'ph-agc'),
			ok = btn('ph-agok', '');
		ag.appendChild(h('div', 'ph-agt', '使用前请确认'));
		ag.appendChild(h('div', 'ph-agb', WARN));
		cb.type = 'checkbox'; cb.id = 'mwrt-ph-agree';
		lb.setAttribute('for', 'mwrt-ph-agree');
		lb.appendChild(cb); lb.appendChild(h('span', '', '我已阅读并愿意承担全部责任'));
		ok.textContent = '进入拨号盘'; ok.disabled = true;
		cb.addEventListener('change', function () { ok.disabled = !cb.checked; });
		ok.addEventListener('click', function () {
			if (!cb.checked) return;
			lsSet(K_AGREE, 'v1'); render();
		});
		ag.appendChild(lb); ag.appendChild(ok);
		dlg.appendChild(ag);

		/* 拨号盘 */
		var pd = h('div', 'ph-v ph-vpad');
		/* s103: IMS 未开启提示条,默认隐藏,由 renderDlg 按 ims===0 显示 */
		els.ims = h('div', 'ph-ims');
		els.ims.setAttribute('role', 'status');
		els.imsT = h('span', 'ph-ims-t', IMS_MSG);
		els.imsGo = h('a', 'ph-ims-go', '去开启');
		if (SMS_SET_URL) els.imsGo.href = SMS_SET_URL; else els.imsGo.style.display = 'none';
		els.ims.appendChild(els.imsT); els.ims.appendChild(els.imsGo);
		pd.appendChild(els.ims);
		els.disp = h('div', 'ph-disp'); els.num = h('div', 'ph-num', '');
		els.disp.appendChild(els.num);
		els.disp.title = '点击从剪贴板粘贴';
		els.disp.addEventListener('click', function () {
			if (navigator.clipboard && navigator.clipboard.readText) {
				navigator.clipboard.readText().then(function (t) { pasteText(t); }, function () { /* 无权限 */ });
			}
		});
		els.err = h('div', 'ph-err', '');
		els.err.setAttribute('role', 'alert');
		pd.appendChild(els.disp); pd.appendChild(els.err);
		var keys = h('div', 'ph-keys');
		var defs = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'], ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'], ['*', ''], ['0', '+'], ['#', '']];
		defs.forEach(function (d) {
			var k = btn('ph-key', d[0] === '*' || d[0] === '#' ? d[0] + ' 键(不支持)' : '数字 ' + d[0]);
			k.appendChild(h('span', 'ph-d', d[0])); k.appendChild(h('span', 'ph-l', d[1]));
			k.setAttribute('data-k', d[0]);
			if (d[0] === '*' || d[0] === '#') {
				k.setAttribute('aria-disabled', 'true'); k.title = '不支持补充业务码';
				k.addEventListener('click', function (e) { e.preventDefault(); });
			} else bindKey(k, d[0]);
			keys.appendChild(k);
		});
		pd.appendChild(keys);
		var ac = h('div', 'ph-acts');
		els.call = btn('ph-call', '拨出'); els.call.appendChild(icon('phone', 32));
		els.bk = btn('ph-bk', '退格'); els.bk.appendChild(icon('back', 26));
		ac.appendChild(els.call); ac.appendChild(els.bk);
		pd.appendChild(ac);
		dlg.appendChild(pd);
		els.call.addEventListener('click', function (e) { if (e.detail) els.call.blur(); doDial(); });
		bindBack(els.bk);

		/* 通话视图 */
		var cv = h('div', 'ph-v ph-vcall'), c2 = h('div', 'ph-cv'), av = h('div', 'ph-av'), cc = h('div', 'ph-cacts');
		av.appendChild(icon('user', 52));
		els.cNum = h('div', 'ph-cnum', ''); els.cSt = h('div', 'ph-cst', ''); els.cTm = h('div', 'ph-ctm', '');
		els.cNote = h('div', 'ph-cnote', '');
		els.cHang = btn('ph-hang', '挂断'); els.cHang.appendChild(icon('phone', 32));
		cc.appendChild(els.cHang); cc.appendChild(h('span', 'ph-cap-l', '挂断'));
		c2.appendChild(av); c2.appendChild(els.cNum); c2.appendChild(els.cSt); c2.appendChild(els.cTm);
		c2.appendChild(els.cNote); c2.appendChild(cc);
		cv.appendChild(c2); dlg.appendChild(cv);
		els.cHang.addEventListener('click', doHangup);

		x.addEventListener('click', closeDlg);
		mask.addEventListener('mousedown', function (e) { if (e.target === mask || e.target === wrap) closeDlg(); });
		wrap.appendChild(dlg); mask.appendChild(wrap); host.appendChild(mask);
		els.mask = mask; els.dlg = dlg; els.cb = cb; els.agok = ok;
	}
	/* 按键:点按输入,0 长按输入 +(仅空号码时) */
	function bindKey(k, ch) {
		var tm = 0, fired = false;
		function down() {
			fired = false;
			if (ch !== '0') return;
			clearTimeout(tm);
			tm = setTimeout(function () {
				if (numStr === '') { fired = true; addChar('+'); }
			}, 500);
		}
		function up() { clearTimeout(tm); }
		k.addEventListener('pointerdown', down);
		k.addEventListener('pointerup', up); k.addEventListener('pointercancel', up); k.addEventListener('pointerleave', up);
		k.addEventListener('contextmenu', function (e) { e.preventDefault(); });
		k.addEventListener('click', function (e) {
			if (fired) { fired = false; return; }
			if (e.detail) k.blur();
			addChar(ch);
		});
	}
	function bindBack(b) {
		var tm = 0, fired = false;
		b.addEventListener('pointerdown', function () {
			fired = false; clearTimeout(tm);
			tm = setTimeout(function () { fired = true; numStr = ''; dialErr = ''; render(); }, 600);
		});
		function up() { clearTimeout(tm); }
		b.addEventListener('pointerup', up); b.addEventListener('pointercancel', up); b.addEventListener('pointerleave', up);
		b.addEventListener('contextmenu', function (e) { e.preventDefault(); });
		b.addEventListener('click', function (e) {
			if (fired) { fired = false; return; }
			if (e.detail) b.blur();
			numStr = numStr.slice(0, -1); dialErr = ''; render();
		});
	}
	function addChar(ch) {
		if (ch === '+') { if (numStr !== '') return; numStr = '+'; }
		else if (/^[0-9]$/.test(ch)) {
			if (numStr.replace(/\D/g, '').length >= 20) return;
			numStr += ch;
		} else return;
		dialErr = ''; render();
	}
	function pasteText(t) {
		t = String(t || '');
		var plus = /^\s*\+/.test(t), d = t.replace(/\D/g, '').slice(0, 20);
		if (!d) return;
		numStr = (plus ? '+' : '') + d; dialErr = ''; render();
	}
	function renderDlg(c, pend, inCall, fake) {
		buildDlg();
		var agreed = lsGet(K_AGREE) === 'v1';
		var v = inCall ? 'call' : (agreed ? 'pad' : 'agree');
		var wasOpen = els.mask.classList.contains('open');
		setCls(els.mask, 'open', true);
		setCls(els.dlg, 'v-pad', v === 'pad'); setCls(els.dlg, 'v-call', v === 'call'); setCls(els.dlg, 'v-agree', v === 'agree');
		setCls(els.test, 'on', fake);
		if (lastView === 'call' && v !== 'call') { numStr = ''; dialNote = ''; }
		if (lastView !== v) {
			lastView = v;
			var f = v === 'agree' ? els.cb : (v === 'call' ? els.cHang : els.call);
			if (wasOpen || true) { try { if (f && !f.disabled) f.focus(); } catch (e) { /* 忽略 */ } }
		}
		/* 拨号盘 */
		var d = numStr.replace(/\D/g, '');
		var shown = numStr ? fmtNum(numStr) : '输入号码';
		setText(els.num, shown);
		setCls(els.num, 'ph-ph', !numStr);
		setCls(els.num, 's2', shown.length > 13 && shown.length <= 17);
		setCls(els.num, 's3', shown.length > 17);
		setCls(els.bk, 'on', numStr !== '');
		var emerg = numStr !== '' && validNum(numStr) && isEmerg(numStr);
		var cool = coolUntil > Date.now();
		var imsOff = imsIsOff();
		var ok = validNum(numStr) && !emerg && !busy.dial && !cool && !imsOff;
		els.call.disabled = !ok;
		/* s103: IMS 未开启 → 提示条 + 拨出键视觉 / 读屏都是禁用(数字键仍可输入) */
		setCls(els.ims, 'on', imsOff);
		if (imsOff) { setAttr(els.call, 'aria-disabled', 'true'); setAttr(els.call, 'title', IMS_BTN_TIP); }
		else { if (els.call.hasAttribute('aria-disabled')) els.call.removeAttribute('aria-disabled'); if (els.call.hasAttribute('title')) els.call.removeAttribute('title'); }
		var msg = dialErr;
		if (!msg && emerg) msg = '不支持拨打紧急号码或短号';
		if (!msg && cool) msg = '请观察状态,30 秒内请勿重复拨打';
		setText(els.err, msg);
		/* 通话视图 */
		if (v === 'call') {
			setText(els.cNum, (c && c.number) ? fmtNum(c.number) : (pend && pendingDial ? fmtNum(pendingDial.number) : '未知号码'));
			setText(els.cSt, statusText(c, pend));
			var tm = '';
			if (c && c.state === 'active') tm = fmtDur(elapsed(c));
			else if (c && c.state === 'ended' && c.answered) tm = '时长 ' + fmtDur(c.dur);
			setText(els.cTm, tm);
			setText(els.cNote, dialNote);
			els.cHang.disabled = !!(c && c.state === 'ended');
			els.cHang.style.opacity = busy.hang ? '.6' : '';
		}
		void d;
		if (cool && !coolTimer) coolTimer = setTimeout(function () { coolTimer = 0; render(); }, Math.max(50, coolUntil - Date.now() + 30));
	}
	function open() {
		if (dead) return;
		if (supported === false) { toast({ kind: 'info', title: '拨号不可用', body: '未检测到可用的 5700 模组' }); return; }
		ensureHost(); buildDlg();
		if (!dlgOpen) { prevFocus = document.activeElement; lastView = ''; }
		dlgOpen = true;
		render();
		if (isLeader) pollNow(); else poke();
	}
	function closeDlg() {
		if (!dlgOpen) return;
		dlgOpen = false; lastView = '';
		if (els.mask) setCls(els.mask, 'open', false);
		try { if (prevFocus && prevFocus.focus) prevFocus.focus(); } catch (e) { /* 忽略 */ }
		render();
	}

	/* ===================== 动作 ===================== */
	function post(name, params, cb, timeout) {
		params = params || {};
		params.token = token();
		req('POST', BASE + '/' + name, form(params), cb, timeout || 15000);
	}
	function fail(d, st, dft) {
		if (d && d.msg) return d.msg;
		if (!st) return '网络错误,请稍后重试';
		return dft + '(HTTP ' + st + ')';
	}
	function doDial() {
		if (busy.dial) return;
		var n = numStr;
		if (!validNum(n) || isEmerg(n) || coolUntil > Date.now() || imsIsOff()) return;
		var prev = rawCall();
		busy.dial = true; dialErr = ''; dialNote = ''; render();
		post('phone_dial', { number: n }, function (d, st) {
			busy.dial = false;
			if (st === 403) { kill(); return; }
			if (d && d.ok) {
				pendingDial = { number: n, t: Date.now(), prevKey: prev ? prev._k : '' };
				if (d.uncertain) { coolUntil = Date.now() + 30000; dialNote = d.msg || '命令超时,呼叫可能已发出,请观察状态,切勿重复拨打'; }
			} else dialErr = fail(d, st, '拨号失败');
			render(); pokeAll();
		}, 25000);
	}
	function doAnswer() {
		var c = viewCall();
		if (!c || c.state !== 'ringing' || busy.ans) return;
		busy.ans = true; ovNote = ''; answerAt = Date.now(); answerKey = c._k; render();
		post('phone_answer', {}, function (d, st) {
			busy.ans = false;
			if (st === 403) { kill(); return; }
			if (!(d && d.ok)) { ovNote = fail(d, st, '接听失败'); answerAt = 0; }
			render(); pokeAll();
		});
	}
	function doHangup() {
		var c = rawCall();
		if (!c || busy.hang) return;
		var k = c._k;
		busy.hang = true; hidKey[k] = Date.now(); ovNote = ''; render();
		post('phone_hangup', {}, function (d, st) {
			busy.hang = false;
			if (st === 403) { kill(); return; }
			if (!(d && d.ok)) {
				delete hidKey[k];
				toast({ kind: 'info', title: '挂断失败', body: fail(d, st, '挂断失败') });
			}
			render(); pokeAll();
		});
	}
	function pokeAll() { if (isLeader) pollNow(); else poke(); }

	/* ===================== toast ===================== */
	function ensureToasts() {
		if (els.toasts) return;
		ensureHost();
		els.toasts = h('div', 'ph-toasts');
		els.toasts.setAttribute('aria-live', 'polite');
		els.more = h('div', 'ph-more', '');
		els.toasts.appendChild(els.more);
		host.appendChild(els.toasts);
	}
	function placeToasts() {
		if (!els.toasts) return;
		var t = els.toasts.style;
		if (window.innerWidth <= 768) {
			var ovT = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--mwrt-ov-t')) || 0;
			var hb = 0, nodes = document.querySelectorAll('header,[class*="header"],[class*="topbar"],[class*="navbar"],[id*="header"]'), i, e, r, cs;
			for (i = 0; i < nodes.length && i < 40; i++) {
				e = nodes[i];
				if (host && host.contains(e)) continue;
				cs = getComputedStyle(e);
				if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
				r = e.getBoundingClientRect();
				if (r.top <= 2 && r.height > 0 && r.height < 140 && r.width >= window.innerWidth * 0.6) hb = Math.max(hb, r.bottom);
			}
			t.top = 'calc(' + (Math.max(ovT, hb, 56) + 8) + 'px + env(safe-area-inset-top,0px))';
			t.left = '';
		} else {
			var left = 12, m = document.querySelector('.main-right,.main,#maincontent,main');
			if (m) { r = m.getBoundingClientRect(); if (r.width > 200) left = Math.max(12, r.left + 12); }
			t.top = '12px'; t.left = left + 'px';
		}
	}
	function toast(o) {
		if (dead) return;
		tQueue.push(o); pumpToasts();
	}
	function pumpToasts() {
		while (tShown.length < 3 && tQueue.length) showToast(tQueue.shift());
		if (els.more) {
			setCls(els.more, 'on', tQueue.length > 0);
			setText(els.more, tQueue.length ? '还有 ' + tQueue.length + ' 条' : '');
			if (els.more.parentNode) els.toasts.appendChild(els.more);
		}
	}
	function showToast(o) {
		ensureToasts(); setTheme(); placeToasts();
		var t = h('div', 'ph-toast ' + (o.kind || 'info')), ic = h('div', 'ph-t-ic'), bd = h('div', 'ph-t-bd'),
			hd = h('div', 'ph-t-hd'), x = btn('ph-t-x', '关闭');
		ic.appendChild(icon(o.kind === 'sms' ? 'msg' : (o.kind === 'miss' ? 'phone' : 'info'), 22));
		hd.appendChild(h('span', 'ph-t-nm', o.title || ''));
		hd.appendChild(h('span', 'ph-t-tm', o.time || '刚刚'));
		bd.appendChild(hd);
		if (o.body) bd.appendChild(h('div', 'ph-t-tx', o.body));
		if (o.full) bd.appendChild(h('div', 'ph-t-full', 'SIM 存储已满'));
		x.appendChild(icon('close', 16));
		t.appendChild(ic); t.appendChild(bd); t.appendChild(x);
		t.setAttribute('role', 'status');
		var rec = { el: t, left: 8000, started: Date.now(), timer: 0 };
		function arm() { rec.started = Date.now(); rec.timer = setTimeout(dismiss, rec.left); }
		function dismiss() {
			clearTimeout(rec.timer);
			var i = tShown.indexOf(rec);
			if (i < 0) return;
			tShown.splice(i, 1);
			t.classList.add('out');
			setTimeout(function () { if (t.parentNode) t.parentNode.removeChild(t); }, 230);
			pumpToasts();
		}
		t.addEventListener('mouseenter', function () { clearTimeout(rec.timer); rec.left = Math.max(1500, rec.left - (Date.now() - rec.started)); });
		t.addEventListener('mouseleave', arm);
		x.addEventListener('click', function (e) { e.stopPropagation(); dismiss(); });
		t.addEventListener('click', function () {
			if (o.kind === 'sms' && SMS_URL) { dismiss(); location.href = SMS_URL; }
			else if (o.kind === 'miss' && o.url) { dismiss(); location.href = o.url; }
			else dismiss();
		});
		tShown.push(rec);
		els.toasts.insertBefore(t, els.more);
		arm();
	}

	/* ===================== 事件去重 / 未读 toast ===================== */
	function lastRec() { return jparse(lsGet(K_LAST)); }
	function ingestEvents(s) {
		var evs = s.events || [], i, ev;
		for (i = 0; i < evs.length; i++) {
			ev = evs[i];
			if (!ev || typeof ev.id !== 'number' || pendingIds[ev.id]) continue;
			pendingIds[ev.id] = 1;
			pendingEv.push({ ev: ev, arrive: s.recvAt, gen: s.data.gen || '' });
		}
	}
	/* s102:通知中心在场就把短信 / 未接来电交给它(它自己按 id + localStorage 已读去重,刷新页面不会重复弹) */
	function noticeCenter() {
		var nc = window.mwrtNotice;
		return nc && typeof nc.refresh === 'function' ? nc : null;
	}
	function flushPending() {
		if (!pendingEv.length || document.visibilityState === 'hidden') return;
		var list = pendingEv.slice().sort(function (a, b) { return a.ev.id - b.ev.id; }), i, p, ev, age, last, cfg, s = curSnap();
		var nc = noticeCenter(), needRefresh = false, isSms, isMiss;
		pendingEv = [];
		cfg = (s && s.data.cfg) || {};
		for (i = 0; i < list.length; i++) {
			p = list[i]; ev = p.ev;
			isSms = ev.type === 'sms';
			isMiss = ev.type === 'call_end' && !ev.answered && ev.reason === 'missed' && ev.dir !== 'out';
			last = lastRec();
			if (last && last.gen === p.gen && ev.id <= last.id) {              /* 其他标签已处理 */
				/* 通知中心每个标签页都有自己的一份卡片,所以别的标签处理过的新事件这里也要刷新一次 */
				if (nc && ((isSms && cfg.sms !== 0) || (isMiss && cfg.call !== 0))) needRefresh = true;
				continue;
			}
			lsSet(K_LAST, JSON.stringify({ gen: p.gen, id: ev.id }));          /* 先写再弹 */
			age = (ev.age || 0) + (Date.now() - p.arrive) / 1000;
			if (age > 600) continue;
			if (isSms) {
				if (cfg.sms === 0) continue;
				if (nc) { needRefresh = true; continue; }
				toast({
					kind: 'sms', title: ev.sender || '新短信', body: ev.text || '', time: fmtAgo(age),
					full: !!(s && s.data.sms && s.data.sms.full)
				});
			} else if (isMiss) {
				if (cfg.call === 0 || age > 60) continue;
				if (nc) { needRefresh = true; continue; }
				toast({ kind: 'miss', title: '未接来电', body: ev.number ? fmtNum(ev.number) : '未知号码', time: fmtAgo(age) });
			}
		}
		if (needRefresh && nc) nc.refresh();
	}

	/* ===================== 快照 / 广播 ===================== */
	function applySnap(s) {
		if (dead || !s || !s.data) return;
		if (snap && s.recvAt <= snap.recvAt) return;
		snap = s;
		if (s.data.supported === false) { onUnsupported(); return; }
		supported = true;
		ingestEvents(s);
		render();
		gotFirst = true;
		flushPending();
	}
	function publish(s) {
		var m = { t: 'snap', from: ID, snap: s };
		if (bc) { try { bc.postMessage(m); } catch (e) { /* 忽略 */ } }
		lsSet(K_SNAP, JSON.stringify(s));
	}
	function poke() {
		if (bc) { try { bc.postMessage({ t: 'poke', from: ID }); } catch (e) { /* 忽略 */ } }
		lsSet(K_POKE, String(Date.now()) + ID);
	}
	function onUnsupported() {
		supported = false;
		syncHomeBtn(false);
		if (dlgOpen) { dlgOpen = false; }
		['cap', 'ov', 'mask', 'toasts'].forEach(function (k) { if (els[k] && els[k].parentNode) els[k].parentNode.removeChild(els[k]); els[k] = null; });
		els = {}; tShown = []; tQueue = [];
	}
	function kill() {
		if (dead) return;
		dead = true;
		stopPolling();
		if (tickTimer) { clearInterval(tickTimer); tickTimer = 0; }
		if (bc) { try { bc.postMessage({ t: 'dead', from: ID }); } catch (e) { /* 忽略 */ } }
		if (host && host.parentNode) host.parentNode.removeChild(host);
		var st = document.getElementById('mwrt-ph-css');
		if (st && st.parentNode) st.parentNode.removeChild(st);
		host = null; els = {};
		syncHomeBtn(false);
	}

	/* ===================== 轮询 / 领头 ===================== */
	function nextDelay() {
		if (failN) return [3000, 6000, 12000, 30000][Math.min(failN, 4) - 1];
		var c = rawCall();
		if (c && c.state !== 'ended') return 1000;
		return document.hidden ? 5000 : 2000;
	}
	function stopPolling() { clearTimeout(pollTimer); pollTimer = 0; }
	function schedule(ms) {
		clearTimeout(pollTimer);
		if (dead || !isLeader) return;
		pollTimer = setTimeout(pollOnce, ms);
	}
	function pollNow() {
		if (dead || !isLeader) return;
		if (polling) { again = true; return; }
		schedule(0);
	}
	function pollOnce() {
		pollTimer = 0;
		if (dead || !isLeader || polling) return;
		polling = true;
		var q = 'hidden=' + (document.hidden ? 1 : 0);
		if (haveBase) q = 'since=' + sinceMem + '&gen=' + encodeURIComponent(genMem) + '&' + q;
		req('GET', BASE + '/phone_state?' + q, null, function (d, st) {
			polling = false;
			if (dead) return;
			if (st === 403) { kill(); return; }
			if (!d) { failN++; schedule(nextDelay()); return; }
			if (d.ok === false) { schedule(nextDelay()); return; }          /* ok:false 不计入退避 */
			failN = 0;
			if (d.supported === false) {
				var s0 = { data: { supported: false, reason: d.reason || '' }, events: [], recvAt: Date.now() };
				applySnap(s0); publish(s0);
				if (!unsupDone) {
					unsupDone = true;
					unsupRetry = setTimeout(function () { unsupRetry = 0; supported = null; snap = null; schedule(0); }, 300000);
				}
				return;
			}
			unsupDone = false;
			var events = d.events || [], i, mx = 0;
			var gotEv = haveBase && d.gen === genMem;
			if (!gotEv) { events = []; sinceMem = d.seq || 0; }
			else for (i = 0; i < events.length; i++) if (events[i].id > mx) mx = events[i].id;
			if (mx > sinceMem) sinceMem = mx;
			if (!haveBase || d.gen !== genMem) {
				var lr = lastRec();
				if (!lr || lr.gen !== d.gen) lsSet(K_LAST, JSON.stringify({ gen: d.gen || '', id: d.seq || 0 }));   /* 落基线,不回放历史 */
			}
			haveBase = true; genMem = d.gen || '';
			delete d.events;
			var s = { data: d, events: events, recvAt: Date.now() };
			applySnap(s); publish(s);
			if (again) { again = false; schedule(0); } else schedule(nextDelay());
		}, 8000);
	}
	function readLead() { return jparse(lsGet(K_LEAD)); }
	function writeLead() { lsSet(K_LEAD, JSON.stringify({ id: ID, ts: Date.now(), vis: !document.hidden })); }
	function leaderTick() {
		if (dead) return;
		var l = readLead(), now = Date.now(), vis = !document.hidden, take = false;
		if (!l || l.id === ID) take = true;
		else if (now - l.ts > 8000) take = true;
		else if (vis && l.vis === false) take = true;
		if (take) {
			writeLead();
			l = readLead();
			if (l && l.id !== ID) take = false;
		}
		if (take && !isLeader) {
			isLeader = true;
			if (!haveBase) {
				var lr = lastRec();
				if (lr) { genMem = lr.gen; sinceMem = lr.id; haveBase = true; }
			}
			schedule(0);
		} else if (!take && isLeader) {
			isLeader = false; stopPolling();
		}
	}

	/* ===================== 键盘 / 粘贴 ===================== */
	function focusables(root) {
		var all = root.querySelectorAll('button,input,a[href],[tabindex="0"]'), out = [], i, e;
		for (i = 0; i < all.length; i++) {
			e = all[i];
			if (e.disabled || e.getAttribute('aria-disabled') === 'true') continue;
			if (!(e.offsetWidth || e.offsetHeight || e.getClientRects().length)) continue;
			out.push(e);
		}
		return out;
	}
	function trapTab(e, root) {
		var f = focusables(root);
		if (!f.length) { e.preventDefault(); return; }
		var a = document.activeElement, i = f.indexOf(a);
		if (e.shiftKey) { if (i <= 0) { e.preventDefault(); f[f.length - 1].focus(); } }
		else if (i < 0 || i === f.length - 1) { e.preventDefault(); f[0].focus(); }
	}
	function onKey(e) {
		if (dead) return;
		if (ovVisible()) {
			if (e.key === 'h' || e.key === 'H') { e.preventDefault(); e.stopPropagation(); doHangup(); }
			else if (e.key === 'Tab') trapTab(e, els.ov);
			else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); }
			return;
		}
		if (!dlgOpen || !els.dlg) return;
		var t = e.target;
		if (t && (t.tagName === 'INPUT' && t.type !== 'checkbox' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
		if (e.key === 'Escape') { e.preventDefault(); closeDlg(); return; }
		if (e.key === 'Tab') { trapTab(e, els.dlg); return; }
		if (e.ctrlKey || e.metaKey || e.altKey) return;
		if (!els.dlg.classList.contains('v-pad')) return;
		if (/^[0-9]$/.test(e.key)) { e.preventDefault(); addChar(e.key); }
		else if (e.key === '+') { e.preventDefault(); addChar('+'); }
		else if (e.key === 'Backspace') { e.preventDefault(); numStr = numStr.slice(0, -1); dialErr = ''; render(); }
		else if (e.key === 'Enter') {
			var a = document.activeElement;
			if (a && a.tagName === 'BUTTON' && els.dlg.contains(a)) return;     /* 焦点在按钮上交给原生 click */
			e.preventDefault(); doDial();
		}
	}

	/* ===================== 对外 API ===================== */
	window.MwrtPhone = {
		version: VERSION,
		open: open,
		close: closeDlg,
		state: function () {
			var s = curSnap(), c = rawCall();
			return {
				supported: supported, leader: isLeader, dialog: dlgOpen,
				state: c ? c.state : 'idle', call: c ? JSON.parse(JSON.stringify(c)) : null,
				sms: s && s.data.sms ? JSON.parse(JSON.stringify(s.data.sms)) : null,
				fake: !!(s && s.data.fake), ims: s ? s.data.ims : undefined
			};
		},
		dbg: function () {
			return { id: ID, leader: isLeader, since: sinceMem, gen: genMem, toasts: tShown.length, queue: tQueue.length, pending: pendingEv.length, failN: failN };
		}
	};

	/* ===================== 启动 ===================== */
	function init() {
		var s0 = jparse(lsGet(K_SNAP));
		if (s0 && s0.recvAt && Date.now() - s0.recvAt < 10000 && s0.data && s0.data.supported !== false) applySnap(s0);
		if (typeof BroadcastChannel === 'function') {
			try {
				bc = new BroadcastChannel('mwrt-phone');
				bc.onmessage = function (m) {
					var d = m.data;
					if (!d || d.from === ID) return;
					if (d.t === 'snap') applySnap(d.snap);
					else if (d.t === 'poke') { if (isLeader) pollNow(); }
					else if (d.t === 'dead') kill();
				};
			} catch (e) { bc = null; }
		}
		window.addEventListener('storage', function (e) {
			if (e.key === K_SNAP && e.newValue) applySnap(jparse(e.newValue));
			else if (e.key === K_POKE) { if (isLeader) pollNow(); }
			else if (e.key === K_LEAD && !e.newValue) leaderTick();
		});
		document.addEventListener('visibilitychange', function () {
			leaderTick();
			if (!document.hidden) { if (isLeader) pollNow(); flushPending(); render(); }
		});
		window.addEventListener('pagehide', function () {
			var l = readLead();
			if (l && l.id === ID) lsDel(K_LEAD);
		});
		window.addEventListener('resize', function () { if (els.toasts) placeToasts(); });
		document.addEventListener('mwrt-theme', function () { if (host) setTheme(); });   // s107: 切换深浅后拨号盘/来电立刻换色
		document.addEventListener('keydown', onKey, true);
		document.addEventListener('paste', function (e) {
			if (!dlgOpen || !els.dlg || !els.dlg.classList.contains('v-pad') || ovVisible()) return;
			var t = e.clipboardData ? e.clipboardData.getData('text') : '';
			e.preventDefault(); pasteText(t);
		});
		leaderTick();
		setInterval(leaderTick, 3000);
	}
	if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
	else init();
})();
