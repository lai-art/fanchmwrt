'use strict';
'require view';
'require rpc';
'require ui';
'require dom';

/* 系统 › 在线更新
 *
 * 后端是 /usr/libexec/rpcd/luci.mwrt-ota。服务器给的标题/说明/描述一律走 E() 的
 * 文本子节点渲染(E 收到字符串时建的是 text node), 不碰 innerHTML —— 说明是后台
 * 人填的, 不能信。
 *
 * 刷写默认"不保留配置"。用户可单独勾选保留 WiFi / 卡槽 / 风扇 / LED 几项关键设置
 * (后端 mwrt-keepcfg 抽成小清单带过去, 新固件首启校验后写回), 整份配置永远不带。
 * 页面上的勾选框 + 最后一次确认弹窗缺一不可, 后端 upgrade 也只认 test 通过的同一个文件, 两头都拦。
 *
 * 小内存机型固件会暂存在 SD 卡; upgrade 只是在后台起准备任务(腾内存 -> 载入固件 -> 刷写),
 * 页面轮询 progress 的 ustate/ustep 显示进展, 准备失败时后端已把服务/无线恢复原样。 */

var callInfo     = rpc.declare({ object: 'luci.mwrt-ota', method: 'info' });
var callLatest   = rpc.declare({ object: 'luci.mwrt-ota', method: 'latest' });
var callCheck    = rpc.declare({ object: 'luci.mwrt-ota', method: 'check' });
var callDownload = rpc.declare({ object: 'luci.mwrt-ota', method: 'download' });
var callProgress = rpc.declare({ object: 'luci.mwrt-ota', method: 'progress' });
var callCancel   = rpc.declare({ object: 'luci.mwrt-ota', method: 'cancel' });
var callVerify   = rpc.declare({ object: 'luci.mwrt-ota', method: 'verify' });
var callTest     = rpc.declare({ object: 'luci.mwrt-ota', method: 'test' });
var callUpgrade  = rpc.declare({ object: 'luci.mwrt-ota', method: 'upgrade', params: [ 'confirm', 'keep' ] });
var callKeepProbe = rpc.declare({ object: 'luci.mwrt-ota', method: 'keep_probe' });
var callSetAuto  = rpc.declare({ object: 'luci.mwrt-ota', method: 'set_auto', params: [ 'enable' ] });

var ERRORS = {
	nonet: _('无法连接更新服务器，请检查网络后重试。'),
	unknown_board: _('无法识别本机机型，暂不支持在线更新。'),
	no_ca: _('缺少更新服务器证书 /etc/mwrt/ota-ca.pem。'),
	no_update: _('当前没有可用的新固件。'),
	bad_url: _('服务器返回的下载地址无效。'),
	bad_sha: _('服务器返回的校验值无效。'),
	bad_size: _('服务器返回的文件大小无效。'),
	no_space: _('可用内存不足，也没有可暂存固件的 SD 卡空间，无法下载。请关闭占用内存的插件（如 OpenClash）后重试。'),
	no_file: _('固件文件不存在，请重新下载。'),
	size_mismatch: _('固件大小不一致，请重新下载。'),
	sha_mismatch: _('固件校验失败（SHA256 不一致），请重新下载。'),
	not_verified: _('固件尚未通过校验。'),
	test_failed: _('固件与本机不兼容，已中止。'),
	not_tested: _('固件尚未通过兼容性检查。'),
	file_changed: _('固件文件在检查后被改动，已中止。'),
	need_confirm: _('需要确认后才能升级。'),
	busy: _('升级正在进行中，请稍候。'),
	no_mem: _('可用内存不足，已取消升级。请关闭占用内存的插件或程序后重试。'),
	swapoff_failed: _('无法关闭 SD 卡上的交换分区，已取消升级。请重启设备后重试。'),
	copy_failed: _('固件载入内存失败，已取消升级。'),
	sysupgrade_failed: _('升级程序未能启动。USB 设备（含模组）可能已被卸载，请重启设备后重试。'),
	dry_run: _('演练完成（未刷写）。'),
	keep_failed: _('要保留的配置打包失败，已取消升级。'),
	bad_keep: _('保留项参数无效。')
};

/* 可单独保留的几项(后端 mwrt-keepcfg probe 给出本机实际有的) */
var KEEP_ITEMS = {
	wifi: _('WiFi 名称、加密方式和密码'),
	simsel: _('卡槽选择'),
	fan: _('风扇设置'),
	led: _('LED 设置')
};
var KEEP_ORDER = [ 'wifi', 'simsel', 'fan', 'led' ];

/* 升级准备任务的步骤(后端 flash 的 step 名) */
var STEPS = {
	start: _('正在检查可用内存…'),
	free_mem: _('正在检查可用内存…'),
	stop_services: _('正在暂停占用内存的插件…'),
	swapoff: _('正在关闭 SD 卡上的交换分区…'),
	wifi_down: _('正在关闭无线以释放内存（无线连接会断开）…'),
	stop_more: _('正在暂停其他非必要服务…'),
	copy: _('正在把固件从 SD 卡载入内存…'),
	check: _('正在复核固件…'),
	restore: _('准备未成功，正在恢复服务…'),
	keep: _('正在打包要保留的配置…'),
	flash: _('开始刷写…')
};
/* 走到这几步时页面断线多半是无线已关, 不必等第二次失败 */
var LATE_STEPS = [ 'wifi_down', 'stop_more', 'copy', 'check', 'keep', 'flash' ];

function errText(res) {
	var e = res && res.error;
	if (!e) return _('未知错误');
	if (ERRORS[e]) return ERRORS[e];
	if (/^http_/.test(e)) return _('更新服务器返回错误（%s）。').format(e.replace('http_', ''));
	return e;
}

function fmtSize(n) {
	n = +n || 0;
	return n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : (n / 1024).toFixed(0) + ' KB';
}

function fmtTime(epoch) {
	epoch = +epoch || 0;
	if (!epoch) return '-';
	var d = new Date(epoch * 1000);
	function p(x) { return x < 10 ? '0' + x : '' + x; }
	return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
}

/* 构建时间: 服务器只知道打包日期时给的是北京时间 0 点, 只显示日期 */
function fmtBuild(epoch) {
	epoch = +epoch || 0;
	if (!epoch || (epoch + 28800) % 86400) return fmtTime(epoch);
	var d = new Date((epoch + 28800) * 1000);
	function p(x) { return x < 10 ? '0' + x : '' + x; }
	return d.getUTCFullYear() + '-' + p(d.getUTCMonth() + 1) + '-' + p(d.getUTCDate());
}

/* 升级准备失败的完整提示 */
function failText(pr) {
	var msg = errText({ error: pr.uerr });
	if (pr.udetail) msg += '（' + pr.udetail + '）';
	if (pr.uerr !== 'sysupgrade_failed' && pr.uerr !== 'dry_run') msg += _('已恢复被暂停的插件和无线，配置未改动。');
	return msg;
}

/* 多行纯文本: 每行一个文本节点 + <br>, 不解析任何标记 */
function multiline(text) {
	var out = [];
	String(text || '').split(/\r?\n/).forEach(function (line, i) {
		if (i) out.push(E('br'));
		out.push(line);
	});
	return out;
}

return view.extend({
	load: function () {
		return Promise.all([ callInfo(), callLatest(), callProgress(),
			L.resolveDefault(callKeepProbe(), { supported: false, items: [] }) ]);
	},

	render: function (data) {
		this.info = data[0] || {};
		this.latest = data[1] || {};
		this.keepProbe = data[3] || { supported: false, items: [] };
		this.box = E('div', { 'id': 'mwrt-ota-latest' });
		this.flow = E('div', { 'id': 'mwrt-ota-flow' });

		var info = this.info;
		var head = E('div', { 'class': 'cbi-section' }, [
			E('h3', _('当前固件')),
			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('机型标识')), E('td', { 'class': 'td left', 'id': 'ota-board' }, info.board || _('未知')) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('固件版本')), E('td', { 'class': 'td left', 'id': 'ota-version' }, info.version || '-') ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('构建时间')), E('td', { 'class': 'td left' }, fmtBuild(info.build)) ])
			])
		]);

		this.autoBox = E('input', {
			'type': 'checkbox', 'id': 'ota-auto',
			'checked': info.auto_check ? '' : null,
			'change': ui.createHandlerFn(this, 'handleAuto')
		});
		this.schedule = E('div', { 'id': 'ota-schedule', 'class': 'cbi-value-description', 'style': 'margin-top:.4em' });
		var ctl = E('div', { 'class': 'cbi-section', 'id': 'ota-control' }, [
			E('h3', _('检查更新')),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:.8em 1.6em' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'id': 'ota-check',
					'click': ui.createHandlerFn(this, 'handleCheck')
				}, _('立即检查')),
				E('label', { 'style': 'display:inline-flex;align-items:center;gap:.5em;cursor:pointer' }, [ this.autoBox, _('自动检查更新') ])
			]),
			E('p', { 'class': 'cbi-value-description', 'style': 'margin-top:.6em' },
				_('开启后每 24 小时自动检查一次（开机或联网恢复后 1 小时内补查），发现新固件只在页面顶部提示，不会自动下载或升级。')),
			this.schedule
		]);
		this.renderSchedule();

		this.renderLatest();

		var self = this, prog = data[2] || {};
		/* 页面刷新时: 正在准备/刷写就接着盯; 后台还在下或已下完, 接着显示进度 */
		if (prog.ustate === 'preparing' || prog.ustate === 'flashing')
			window.setTimeout(function () { self.watchFlash(); }, 0);
		else if (prog.state === 'running' || prog.state === 'done') {
			if (prog.ustate === 'failed') this.lastFail = prog;
			window.setTimeout(function () { self.startFlow(true); }, 0);
		}

		return E([], [
			E('h2', _('在线更新')),
			E('div', { 'class': 'cbi-map-descr' }, _('根据本机机型自动查找适配的新固件。升级默认不保留配置，可单独勾选保留 WiFi、卡槽、风扇、LED 设置。')),
			head, ctl, this.box, this.flow
		]);
	},

	/* 上次检查 / 下次自动检查 / 上次失败原因 */
	renderSchedule: function () {
		var i = this.info, rows = [];
		rows.push(E('div', { 'id': 'ota-last' }, _('上次成功检查：%s').format(i.last_ok ? fmtTime(i.last_ok) : _('本次开机尚未检查'))));
		if (i.last_err && i.last_try && i.last_try >= (i.last_ok || 0))
			rows.push(E('div', { 'id': 'ota-last-err', 'style': 'color:#c62828' },
				_('最近一次检查失败（%s）：%s').format(fmtTime(i.last_try), errText({ error: i.last_err }))));
		rows.push(E('div', { 'id': 'ota-next' }, i.auto_check
			? _('下次自动检查：约 %s').format(i.next_check ? fmtTime(i.next_check) : _('1 小时内'))
			: _('自动检查已关闭，仅在点「立即检查」时联网。')));
		dom.content(this.schedule, rows);
	},

	refreshInfo: function () {
		var self = this;
		return callInfo().then(function (i) {
			if (i && i.ok) { self.info = i; self.renderSchedule(); }
		});
	},

	handleAuto: function (ev) {
		var self = this, box = ev.target, want = box.checked;
		box.disabled = true;
		return callSetAuto(want ? '1' : '0').then(function (i) {
			if (!i || !i.ok) throw new Error(errText(i));
			self.info = i;
			box.checked = !!i.auto_check;
			self.renderSchedule();
			ui.addTimeLimitedNotification(null, E('p', i.auto_check ? _('已开启自动检查更新') : _('已关闭自动检查更新')), 3000, 'info');
		}).catch(function (e) {
			box.checked = !want;
			ui.addNotification(null, E('p', _('保存失败：%s').format(e.message || e)), 'danger');
		}).finally(function () {
			box.disabled = false;
		});
	},

	renderLatest: function () {
		var l = this.latest, box = this.box;
		dom.content(box, []);
		if (!l || !l.checked) {
			box.appendChild(E('div', { 'class': 'cbi-section' }, E('p', { 'class': 'cbi-value-description' }, _('尚未检查更新。'))));
			return;
		}
		if (!l.update) {
			box.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('p', { 'id': 'ota-uptodate' }, _('当前已是最新固件。')),
				E('p', { 'class': 'cbi-value-description' }, _('上次检查：%s').format(fmtTime(l.checked_at)))
			]));
			return;
		}

		this.ack = E('input', { 'type': 'checkbox', 'id': 'ota-ack', 'change': ui.createHandlerFn(this, function (ev) {
			/* 流程已经开始(或页面刷新后接着跑)时不能再点, 否则会再起一次下载 */
			document.getElementById('ota-accept').disabled = !ev.target.checked || !!this.flowStarted;
		}) });

		var rows = [
			[ _('新版本'), l.version ],
			[ _('构建时间'), fmtBuild(l.build) ],
			[ _('文件大小'), fmtSize(l.size) ],
			[ _('发布时间'), fmtTime(l.published) ],
			[ 'SHA256', l.sha256 ]
		];

		box.appendChild(E('div', { 'class': 'cbi-section', 'id': 'ota-new' }, [
			E('h3', { 'id': 'ota-title' }, l.title || _('新固件')),
			E('table', { 'class': 'table' }, rows.map(function (r) {
				return E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, r[0]), E('td', { 'class': 'td left', 'style': 'word-break:break-all' }, r[1] || '-') ]);
			})),
			l.notes ? E('div', { 'style': 'margin-top:1em' }, [ E('h4', _('更新说明')), E('div', { 'id': 'ota-notes', 'style': 'white-space:normal;line-height:1.7' }, multiline(l.notes)) ]) : '',
			l.description ? E('div', { 'style': 'margin-top:1em' }, [ E('h4', _('描述')), E('div', { 'id': 'ota-desc', 'style': 'line-height:1.7' }, multiline(l.description)) ]) : '',
			this.renderKeep(),
			E('div', { 'class': 'alert-message warning', 'style': 'margin-top:1.2em' }, [
				E('strong', _('注意：除上面勾选保留的项目外，其余配置全部恢复出厂默认。')),
				E('br'),
				_('管理地址、登录密码、网络、模组拨号、插件等设置不会保留，请提前记录需要的配置。升级过程中切勿断电。')
			]),
			E('label', { 'style': 'display:inline-flex;align-items:center;gap:.5em;margin:.8em 0' }, [ this.ack, _('我已知晓未保留的配置将恢复出厂默认') ]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'id': 'ota-accept',
					'disabled': true,
					'click': ui.createHandlerFn(this, function () { return this.startFlow(false); })
				}, _('接受更新'))
			])
		]));
	},

	/* 保留项: 四项各一个勾选框 + 「全部不保存」, 两边互斥; 默认全部不保存 */
	renderKeep: function () {
		var self = this, pr = this.keepProbe || {}, avail = pr.items || [];
		var items = KEEP_ORDER.filter(function (k) { return avail.indexOf(k) >= 0; });
		this.keepBoxes = {};
		if (!pr.supported || !items.length) {
			this.keepNone = null;
			return E('div', { 'id': 'ota-keep', 'style': 'margin-top:1.2em' }, [
				E('h4', _('升级时保留的配置')),
				E('p', { 'class': 'cbi-value-description' }, _('当前固件不支持保留配置升级，将以不保留配置的方式刷写。'))
			]);
		}
		function lab(box, text) {
			return E('label', { 'style': 'display:inline-flex;align-items:center;gap:.45em;cursor:pointer' }, [ box, text ]);
		}
		this.keepNone = E('input', { 'type': 'checkbox', 'id': 'ota-keep-none', 'checked': '', 'change': function (ev) {
			if (ev.target.checked) items.forEach(function (k) { self.keepBoxes[k].checked = false; });
			else if (!self.keepList().length) ev.target.checked = true;
		} });
		var row = items.map(function (k) {
			var b = E('input', { 'type': 'checkbox', 'id': 'ota-keep-' + k, 'change': function () {
				self.keepNone.checked = !self.keepList().length;
			} });
			self.keepBoxes[k] = b;
			return lab(b, KEEP_ITEMS[k]);
		});
		row.push(lab(this.keepNone, _('全部不保存')));
		return E('div', { 'id': 'ota-keep', 'style': 'margin-top:1.2em' }, [
			E('h4', _('升级时保留的配置')),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:.6em 1.6em' }, row),
			E('p', { 'class': 'cbi-value-description', 'style': 'margin-top:.5em' },
				_('只保留勾选项的关键设置，新固件首次启动时逐项校验后写回，不兼容的值会自动放弃并保持出厂默认。'))
		]);
	},

	keepList: function () {
		var b = this.keepBoxes || {};
		return KEEP_ORDER.filter(function (k) { return b[k] && b[k].checked; });
	},

	keepNames: function (list) {
		return list.map(function (k) { return KEEP_ITEMS[k]; }).join('、');
	},

	handleCheck: function () {
		var self = this;
		return callCheck().then(function (res) {
			if (!res || !res.ok) {
				ui.addNotification(null, E('p', errText(res)), 'warning');
				return;
			}
			/* 流程进行中不重画新版区域, 否则勾选框/接受按钮会被重新放开 */
			if (!self.flowStarted) {
				self.latest = res;
				self.renderLatest();
			}
			if (!res.update)
				ui.addTimeLimitedNotification(null, E('p', _('当前已是最新固件。')), 3000, 'info');
		}).finally(function () {
			return self.refreshInfo();
		});
	},

	setStep: function (text, pct) {
		dom.content(this.stepText, text);
		if (pct != null) {
			this.bar.style.width = pct + '%';
			this.bar.parentNode.setAttribute('title', pct + '%');
			this.bar.parentNode.setAttribute('data-pct', pct);
		}
	},

	failFlow: function (res) {
		this.setStep(E('span', { 'style': 'color:#c62828' }, errText(res)));
		dom.content(this.flowBtns, E('button', {
			'class': 'btn cbi-button',
			'click': ui.createHandlerFn(this, function () {
				return callCancel().then(function () { location.reload(); });
			})
		}, _('清除并重试')));
	},

	buildFlow: function () {
		this.bar = E('div', { 'style': 'height:100%;width:0;background:#1e88e5;transition:width .4s' });
		this.stepText = E('p', { 'id': 'ota-step' }, _('准备下载…'));
		this.flowBtns = E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(this, function () {
				return callCancel().then(function () { location.reload(); });
			}) }, _('取消'))
		]);
		dom.content(this.flow, E('div', { 'class': 'cbi-section' }, [
			E('h3', _('升级进度')),
			E('div', { 'id': 'ota-bar', 'style': 'height:14px;border-radius:7px;background:rgba(127,127,127,.2);overflow:hidden' }, this.bar),
			this.stepText,
			this.flowBtns
		]));
		this.flowStarted = true;
		var accept = document.getElementById('ota-accept');
		if (accept) accept.disabled = true;
		if (this.ack) this.ack.disabled = true;
	},

	startFlow: function (resume) {
		var self = this;
		this.buildFlow();

		var p = resume ? Promise.resolve({ ok: true }) : callDownload();
		return p.then(function (res) {
			if (!res || !res.ok) return self.failFlow(res);
			return self.pollDownload();
		});
	},

	pollDownload: function () {
		var self = this;
		return new Promise(function (resolve) {
			function tick() {
				callProgress().then(function (pr) {
					var got = +pr.got || 0, total = +pr.total || 0;
					var pct = total ? Math.min(100, Math.floor(got * 100 / total)) : 0;
					if (pr.state === 'running') {
						self.setStep((pr.where === 'sd' ? _('正在下载到 SD 卡 %s / %s') : _('正在下载 %s / %s')).format(fmtSize(got), fmtSize(total)), pct);
						window.setTimeout(tick, 1500);
					} else if (pr.state === 'done') {
						self.setStep(_('下载完成，正在校验…'), 100);
						resolve(self.verifyAndTest());
					} else {
						resolve(self.failFlow({ error: pr.state === 'failed' ? _('下载失败（curl %s），请重试。').format(pr.rc || '?') : _('下载未开始') }));
					}
				}).catch(function () { window.setTimeout(tick, 3000); });
			}
			tick();
		});
	},

	verifyAndTest: function () {
		var self = this;
		return callVerify().then(function (v) {
			if (!v || !v.ok) return self.failFlow(v);
			self.setStep(_('校验通过，正在检查固件兼容性…'), 100);
			return callTest().then(function (t) {
				if (!t || !t.ok) return self.failFlow(t);
				var ready = [ v.where === 'sd'
					? _('固件已就绪：SHA256 校验通过，兼容性检查通过。固件暂存在 SD 卡上，开始升级时再载入内存。')
					: _('固件已就绪：SHA256 校验通过，兼容性检查通过。') ];
				if (self.lastFail) {
					ready.push(E('br'), E('span', { 'style': 'color:#c62828' }, _('上次升级未成功：%s').format(failText(self.lastFail))));
					self.lastFail = null;
				}
				self.setStep(ready, 100);
				dom.content(self.flowBtns, [
					E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(self, function () {
						return callCancel().then(function () { location.reload(); });
					}) }, _('放弃')),
					' ',
					E('button', { 'class': 'btn cbi-button cbi-button-negative', 'id': 'ota-flash',
						'click': ui.createHandlerFn(self, 'confirmFlash') }, _('开始升级'))
				]);
			});
		});
	},

	confirmFlash: function () {
		var self = this, keep = this.keepList();
		ui.showModal(_('确认升级'), [
			E('p', { 'id': 'ota-final' }, [
				E('strong', keep.length ? _('即将刷写新固件，并保留：%s。').format(this.keepNames(keep))
					: _('即将以不保留配置的方式刷写新固件。')),
				E('br'),
				keep.length ? _('其余设置将恢复出厂默认，过程约需 3～5 分钟，期间切勿断电。')
					: _('全部设置将恢复出厂默认，过程约需 3～5 分钟，期间切勿断电。'),
				E('br'),
				_('为腾出内存，开始前会暂停 OpenClash 等占用内存的插件，必要时关闭无线（经无线连接的设备会断开）；准备不成功会自动恢复。确定继续吗？')
			]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn cbi-button', 'id': 'ota-final-cancel', 'click': ui.hideModal }, _('取消')),
				' ',
				E('button', { 'class': 'btn cbi-button cbi-button-negative', 'id': 'ota-final-ok', 'click': ui.createHandlerFn(self, 'doFlash') }, _('确定升级'))
			])
		]);
	},

	doFlash: function () {
		var self = this;
		var keep = this.keepList();
		/* 开刷后勾选不能再改: 后端已按这次的选择起任务 */
		Object.keys(this.keepBoxes || {}).forEach(function (k) { self.keepBoxes[k].disabled = true; });
		if (this.keepNone) this.keepNone.disabled = true;
		this.flashKeep = keep;
		return callUpgrade('yes', keep.join(',')).then(function (res) {
			if (!res || !res.ok) {
				ui.hideModal();
				ui.addNotification(null, E('p', errText(res)), 'danger');
				return;
			}
			self.watchFlash();
		});
	},

	/* 准备阶段可能关无线, 经无线打开的页面会断线: 断线就按"已开始刷写"倒计时,
	 * 但继续悄悄轮询 —— 准备失败、无线恢复后还能把失败原因报出来 */
	watchFlash: function () {
		var self = this, misses = 0, counting = false, left = 300, timer = null, done = false, lastStep = '';
		var stepEl = E('p', { 'class': 'spinning', 'id': 'ota-prep' }, _('正在准备升级…'));
		ui.showModal(_('正在准备升级'), [
			stepEl,
			E('p', { 'class': 'cbi-value-description' }, _('正在为刷写腾出内存，可能会暂停部分插件并关闭无线，请勿断电。'))
		]);

		function countdown(note) {
			if (counting) return;
			counting = true;
			var cd = E('strong', '' + left);
			ui.showModal(_('正在升级'), [
				E('p', { 'class': 'spinning' }, _('固件正在刷写，请勿断电。设备会自动重启。')),
				E('p', [ (self.flashKeep && self.flashKeep.length)
					? _('已保留%s，其余配置恢复出厂，重启后请使用出厂地址访问，剩余约 ').format(self.keepNames(self.flashKeep))
					: _('配置已清除，重启后请使用出厂地址访问，剩余约 '), cd, _(' 秒') ]),
				note ? E('p', { 'class': 'cbi-value-description', 'id': 'ota-lost' }, note) : ''
			]);
			timer = window.setInterval(function () {
				left--;
				cd.textContent = '' + Math.max(0, left);
				if (left <= 0) { window.clearInterval(timer); done = true; }
			}, 1000);
		}

		function tick() {
			if (done) return;
			callProgress().then(function (pr) {
				pr = pr || {};
				misses = 0;
				if (pr.ustate === 'failed') {
					done = true;
					if (timer) window.clearInterval(timer);
					ui.hideModal();
					self.flashFailed(pr);
					return;
				}
				if (pr.ustate === 'flashing')
					countdown();
				else if (!counting) {
					lastStep = pr.ustep || '';
					dom.content(stepEl, STEPS[lastStep] || _('正在准备升级…'));
				}
				window.setTimeout(tick, counting ? 3000 : 1500);
			}).catch(function () {
				if (++misses >= 2 || LATE_STEPS.indexOf(lastStep) >= 0)
					countdown(_('与路由器的连接已断开（准备阶段会关闭无线），升级应已开始。'));
				window.setTimeout(tick, 3000);
			});
		}
		tick();
	},

	flashFailed: function (pr) {
		var self = this;
		if (!this.stepText) this.buildFlow();
		Object.keys(this.keepBoxes || {}).forEach(function (k) { self.keepBoxes[k].disabled = false; });
		if (this.keepNone) this.keepNone.disabled = false;
		var retry = [ 'sysupgrade_failed', 'not_tested', 'file_changed', 'copy_failed' ].indexOf(pr.uerr) < 0;
		this.setStep(E('span', { 'style': 'color:#c62828' }, failText(pr)));
		dom.content(this.flowBtns, [
			E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(this, function () {
				return callCancel().then(function () { location.reload(); });
			}) }, _('清除并重新下载')),
			retry ? ' ' : '',
			retry ? E('button', { 'class': 'btn cbi-button cbi-button-negative', 'id': 'ota-flash',
				'click': ui.createHandlerFn(this, 'confirmFlash') }, _('重试升级')) : ''
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
