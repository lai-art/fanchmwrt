// /usr/libexec/mwrt-notice-ack.uc  (s105)
//
// 短信 / 未接来电通知的「已读」写端。已读记在设备端 /tmp/mwrt-phone/notice.ack(追加式, 一行一个卡片 id),
// luci.mwrt-notice 出卡时读它, 已读的卡不再出, 所有浏览器看到的一致。
//
// 用法(由 luci.controller.modem 的 notice_ack 接口调用, 参数已在那边校验过一遍, 这里再严格校验一遍):
//   ucode mwrt-notice-ack.uc ids <键> [<键> ...]          把这些卡片 id 标为已读(最多 50 个)
//   ucode mwrt-notice-ack.uc scope sms|miss|all [upto=N]  把 events 里当前所有该类事件标为已读;
//                                                         带 upto 时只标事件 id <= N 的(收件箱用: 只标读取开始前就已到达的)
//   ucode mwrt-notice-ack.uc scope sms_older|older keep=<键>[,<键>...]
//                                                         汇总卡的 ×: 只标「比 keep 里最老一张还老」的未读事件
//                                                         (按 ts 再按事件 id, 与出卡排序一致), 最新的几张和之后新到的不动。
//                                                         sms_older 只管短信, older 短信 + 未接来电。
// 输出一行 JSON: {"ok":true,"added":N} 或 {"ok":false,"error":"..."}; 失败退出码非 0。
//
// 键 = 卡片 id: sms-<事件id>-<ts> / miss-<事件id>-<ts>。事件 id 守护重启后会续计(seq 文件), 且键里带 ts,
// 板子重启后 /tmp 整个清空(ack 与 events 一起没), 所以键不会误伤新事件。
//
// 并发 / 原子性:
//  - 整个读-改-写在 notice.ack.lock 的 flock 里完成(轮询最多约 3 秒, 拿不到就报错, 不死等);
//  - 追加是一次 write(O_APPEND), 之后行数超过 600(或文件超过 64KB)时在锁内压缩到最近 300 条有效行:
//    先写同目录的临时文件(0600, O_EXCL), 再 rename 原子替换, 读端要么读到旧文件要么读到新文件;
//  - 目录必须是 root 属主的真目录(不是符号链接); ack 文件若是符号链接 / 非普通文件 / 非 root 属主就先删掉重建
//    (unlink 删的是链接本身, 不会写到链接指向的文件); 文件权限固定 0600。
//
// 可用环境变量改路径(仅测试用, 生产不设): PHONE_EVENTS PHONE_ACK

import { open, lstat, unlink, rename, mkdir, chmod, readfile } from 'fs';

const EVENTS = getenv('PHONE_EVENTS') || '/tmp/mwrt-phone/events';
const ACK = getenv('PHONE_ACK') || '/tmp/mwrt-phone/notice.ack';
const LOCK = ACK + '.lock';
const READ_LINES = 400;        // 读端只认最后这么多行(与 luci.mwrt-notice 一致)
const READ_BYTES = 32768;      // 读尾部这么多字节
const COMPACT_OVER = 600;      // 超过这么多行压缩
const COMPACT_KEEP = 300;      // 压缩后留这么多行
const COMPACT_BYTES = 65536;   // 文件超过这么大也压缩(防垃圾行撑大)
const MAX_IDS = 50;
const EVENTS_TAIL = 262144;

function out(o, rc) {
	print(sprintf('%J', o), '\n');
	exit(rc);
}

function fail(msg) {
	out({ ok: false, error: msg }, 1);
}

function valid_key(k) {
	return type(k) == 'string' && length(k) <= 40 && match(k, /^(sms|miss)-[0-9]{1,10}-[0-9]{1,12}$/) != null;
}

// 读文件尾部, 返回有效行(键)数组; 文件缺失 / 不可读返回 []
function tail_keys(path, maxlines) {
	let st = lstat(path);
	if (!st || st.type != 'file') return [];
	let data = '';
	if (st.size <= READ_BYTES) {
		data = readfile(path, READ_BYTES) ?? '';
	} else {
		let f = open(path, 'r');
		if (!f) return [];
		f.seek(st.size - READ_BYTES, 0);
		data = f.read(READ_BYTES) ?? '';
		f.close();
		let nl = index(data, '\n');
		data = nl >= 0 ? substr(data, nl + 1) : '';
	}
	let ls = split(data, '\n'), res = [];
	for (let l in ls) {
		l = trim(l);
		if (valid_key(l)) push(res, l);
	}
	return length(res) > maxlines ? slice(res, length(res) - maxlines) : res;
}

// 与 luci.mwrt-notice 出卡逻辑相同的事件枚举: 返回 [{key, kind, id, ts}]
function enum_events() {
	let st = lstat(EVENTS), data;
	if (!st || st.type != 'file' || !(st.size > 0)) return [];
	if (st.size <= EVENTS_TAIL) {
		data = readfile(EVENTS, EVENTS_TAIL) ?? '';
	} else {
		let f = open(EVENTS, 'r');
		if (!f) return [];
		f.seek(st.size - EVENTS_TAIL, 0);
		data = f.read(EVENTS_TAIL) ?? '';
		f.close();
		let nl = index(data, '\n');
		data = nl >= 0 ? substr(data, nl + 1) : '';
	}
	let res = [], seen = {};
	for (let line in split(data, '\n')) {
		line = trim(line);
		if (substr(line, 0, 1) != '{') continue;
		let ev = null;
		try { ev = json(line); } catch (e) { ev = null; }
		if (type(ev) != 'object') continue;
		let ts = int(ev.ts);
		if (!(ts > 0)) continue;
		let id = int(ev.id);
		if (!(id >= 0)) id = 0;
		let kind = null;
		if (ev.type == 'sms') kind = 'sms';
		else if (ev.type == 'call_end' && ev.reason == 'missed' && ev.dir != 'out' && !ev.answered) kind = 'miss';
		if (!kind) continue;
		let key = `${kind}-${id}-${ts}`;
		if (seen[key] || !valid_key(key)) continue;
		seen[key] = true;
		push(res, { key: key, kind: kind, id: id, ts: ts });
	}
	return res;
}

// ---------- 参数解析 ----------
const args = ARGV;
let mode = args[0], keys = [];

if (mode == 'ids') {
	let list = slice(args, 1);
	if (!length(list)) fail('没有指定要标记的消息');
	if (length(list) > MAX_IDS) fail('一次最多标记 ' + MAX_IDS + ' 条');
	for (let k in list) {
		if (!valid_key(k)) fail('消息编号不合法');
		push(keys, k);
	}
} else if (mode == 'scope') {
	let scope = args[1], upto = null, keep = [];
	if (scope != 'sms' && scope != 'miss' && scope != 'all' && scope != 'sms_older' && scope != 'older') fail('范围不合法');
	for (let a in slice(args, 2)) {
		let m;
		if ((m = match(a, /^upto=([0-9]{1,10})$/))) upto = int(m[1]);
		else if ((m = match(a, /^keep=(.*)$/))) {
			for (let k in split(m[1], ',')) {
				if (!valid_key(k)) fail('保留的消息编号不合法');
				push(keep, k);
			}
			if (length(keep) > 10) fail('保留的消息过多');
		} else fail('参数不合法');
	}
	let older = (scope == 'sms_older' || scope == 'older');
	if (older && upto != null) fail('参数不合法');
	if (!older && length(keep)) fail('参数不合法');
	if (!older && upto != null && upto < 0) fail('参数不合法');
	// 汇总卡: 以 keep 里最老的一张(ts 最小, 同秒事件 id 最小)为界
	let cut = null;
	if (older) {
		if (!length(keep)) fail('缺少已显示的消息');
		for (let k in keep) {
			let m = match(k, /^(sms|miss)-([0-9]+)-([0-9]+)$/);
			let c = { id: int(m[2]), ts: int(m[3]) };
			if (!cut || c.ts < cut.ts || (c.ts == cut.ts && c.id < cut.id)) cut = c;
		}
	}
	for (let e in enum_events()) {
		if (scope == 'sms' || scope == 'sms_older') { if (e.kind != 'sms') continue; }
		else if (scope == 'miss') { if (e.kind != 'miss') continue; }
		if (upto != null && e.id > upto) continue;
		if (cut && !(e.ts < cut.ts || (e.ts == cut.ts && e.id < cut.id))) continue;
		push(keys, e.key);
	}
} else {
	fail('用法不对');
}

// ---------- 目录 / 锁 / 追加 / 压缩 ----------
function dirname_of(p) {
	let i = rindex(p, '/');
	return i > 0 ? substr(p, 0, i) : '/';
}

const DIR = dirname_of(ACK);
let dst = lstat(DIR);
if (!dst) {
	mkdir(DIR, 0755);
	dst = lstat(DIR);
}
if (!dst || dst.type != 'directory') fail('状态目录不可用');
if (dst.uid != 0) fail('状态目录属主不对');

// 普通文件、root 属主才保留; 其余(符号链接 / 目录 / 管道 / 别人的文件)删掉重建
function clean_node(p) {
	let s = lstat(p);
	if (s && (s.type != 'file' || s.uid != 0)) {
		unlink(p);
		return null;
	}
	return s;
}

clean_node(LOCK);
let lk = open(LOCK, 'a', 0600);
if (!lk) fail('无法创建锁文件');
let got = false;
for (let i = 0; i < 30; i++) {
	if (lk.lock('xn')) { got = true; break; }
	sleep(100);
}
if (!got) fail('其它进程正在写入, 请稍后重试');

let added = 0;

let ast = clean_node(ACK);
let have = {};
for (let k in tail_keys(ACK, READ_LINES)) have[k] = true;
let fresh = [], dup = {};
for (let k in keys) {
	if (have[k] || dup[k]) continue;
	dup[k] = true;
	push(fresh, k);
}

if (length(fresh)) {
	let f = open(ACK, 'a', 0600);
	if (!f) { lk.close(); fail('无法写入已读记录'); }
	// 一次 write, O_APPEND: 读端要么看到整批要么看不到(行数 <= 50, 远小于 PIPE_BUF 之外也无妨, 持锁中)
	f.write(join('\n', fresh) + '\n');
	f.flush();
	f.close();
	chmod(ACK, 0600);
	added = length(fresh);
}

// 压缩
ast = lstat(ACK);
if (ast && ast.type == 'file') {
	let all = tail_keys(ACK, 1000000);      // 只会读到尾部 64KB 以内的有效行
	if (length(all) > COMPACT_OVER || ast.size > COMPACT_BYTES) {
		let keepn = slice(all, length(all) > COMPACT_KEEP ? length(all) - COMPACT_KEEP : 0);
		// 持锁期间只有一个写者, 临时文件名固定; 先删掉可能残留(或被人换成符号链接)的旧名再 O_EXCL 新建
		let tmp = ACK + '.tmp';
		unlink(tmp);
		let t = open(tmp, 'wx', 0600);
		if (t) {
			t.write(length(keepn) ? join('\n', keepn) + '\n' : '');
			t.flush();
			t.close();
			if (!rename(tmp, ACK)) unlink(tmp);
		}
	}
}

lk.lock('u');
lk.close();
out({ ok: true, added: added }, 0);
