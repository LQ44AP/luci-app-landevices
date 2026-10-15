#!/usr/bin/ucode

'use strict';

import { readfile, popen } from 'fs';

const VENDOR_FILE = '/usr/share/luci-app-landevices/data.csv';

/* ==================================================================== */
/*  Helpers                                                             */
/* ==================================================================== */

function run(cmd) {
	let p = popen(cmd, 'r');
	if (!p)
		return '';
	let out = p.read('all');
	p.close();
	return out || '';
}

function tokenize(line) {
	let res = [];
	let cur = null;

	for (let i = 0; i < length(line); i++) {
		let ch = substr(line, i, 1);
		if (ch == ' ' || ch == '\t') {
			if (cur != null) {
				push(res, cur);
				cur = null;
			}
		}
		else {
			if (cur == null)
				cur = '';
			cur += ch;
		}
	}

	if (cur != null)
		push(res, cur);

	return res;
}

function push_unique(arr, val) {
	for (let i = 0; i < length(arr); i++)
		if (arr[i] == val)
			return;
	push(arr, val);
}

function norm_mac(m) {
	let hex = '';
	let s = lc(m);

	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
			hex += c;
	}

	if (length(hex) != 12)
		return null;

	let out = '';
	for (let i = 0; i < 12; i += 2) {
		if (i > 0)
			out += ':';
		out += uc(substr(hex, i, 2));
	}

	return out;
}

function strip_colons(mac) {
	let out = '';
	for (let i = 0; i < length(mac); i++) {
		let c = substr(mac, i, 1);
		if (c != ':')
			out += c;
	}
	return out;
}

/* ==================================================================== */
/*  Vendor lookup                                                       */
/* ==================================================================== */

let vendor6 = null;
let vendor7 = null;
let vendor9 = null;

function load_vendor_data() {
	if (vendor6 != null)
		return;

	vendor6 = {};
	vendor7 = {};
	vendor9 = {};

	let data = readfile(VENDOR_FILE);
	if (!data)
		return;

	let lines = split(data, '\n');

	for (let i = 0; i < length(lines); i++) {
		let line = trim(lines[i]);
		if (line == '')
			continue;

		let comma = index(line, ',');
		if (comma < 1)
			continue;

		let prefix = uc(trim(substr(line, 0, comma)));
		let name = trim(substr(line, comma + 1));

		if (substr(name, 0, 1) == '"' && substr(name, length(name) - 1, 1) == '"')
			name = substr(name, 1, length(name) - 2);

		if (prefix == '' || name == '')
			continue;

		let len = length(prefix);
		if (len == 6)
			vendor6[prefix] = name;
		else if (len == 7)
			vendor7[prefix] = name;
		else if (len == 9)
			vendor9[prefix] = name;
	}
}

function lookup_vendor(mac) {
	let hex = uc(strip_colons(mac));

	if (length(hex) < 6)
		return 'Unknown';

	let k;

	k = substr(hex, 0, 9);
	if (vendor9 != null && vendor9[k] != null)
		return vendor9[k];

	k = substr(hex, 0, 7);
	if (vendor7 != null && vendor7[k] != null)
		return vendor7[k];

	k = substr(hex, 0, 6);
	if (vendor6 != null && vendor6[k] != null)
		return vendor6[k];

	return 'Unknown';
}

/* ==================================================================== */
/*  Neighbour / lease parsers                                           */
/* ==================================================================== */

function parse_arp() {
	let result = {};
	let data = readfile('/proc/net/arp');
	if (!data)
		return result;

	let lines = split(data, '\n');

	for (let i = 1; i < length(lines); i++) {
		let line = trim(lines[i]);
		if (line == '')
			continue;

		let f = tokenize(line);
		if (length(f) < 4)
			continue;

		let ip = f[0];
		let flags = lc(f[2]);
		let rawmac = f[3];

		let mac = norm_mac(rawmac);
		if (mac == null || mac == '00:00:00:00:00:00')
			continue;

		if (result[mac] == null)
			result[mac] = { online: false, ips: [] };

		if (substr(flags, 0, 2) == '0x')
			flags = substr(flags, 2);
		if (hex(flags) == 2)
			result[mac].online = true;

		push_unique(result[mac].ips, ip);
	}

	return result;
}

function parse_nd6() {
	let result = {};
	let out = run('ip -6 neigh show 2>/dev/null');
	if (out == '')
		return result;

	let lines = split(out, '\n');

	for (let i = 0; i < length(lines); i++) {
		let line = trim(lines[i]);
		if (line == '')
			continue;

		let f = tokenize(line);
		if (length(f) < 2)
			continue;

		let addr = f[0];
		let state = f[length(f) - 1];
		let rawmac = null;

		for (let j = 0; j < length(f) - 1; j++) {
			if (f[j] == 'lladdr') {
				rawmac = f[j + 1];
				break;
			}
		}

		if (rawmac == null)
			continue;

		let mac = norm_mac(rawmac);
		if (mac == null || mac == '00:00:00:00:00:00')
			continue;

		if (result[mac] == null)
			result[mac] = { online: false, ips: [] };

		if (state != 'FAILED')
			result[mac].online = true;

		push_unique(result[mac].ips, addr);
	}

	return result;
}

function parse_leases() {
	let result = {};
	let data = readfile('/tmp/dhcp.leases');
	if (!data)
		return result;

	let lines = split(data, '\n');

	for (let i = 0; i < length(lines); i++) {
		let line = trim(lines[i]);
		if (line == '')
			continue;

		let f = tokenize(line);
		if (length(f) < 4)
			continue;

		let rawmac = f[1];
		let name = f[3];

		if (name == '*')
			continue;

		let mac = norm_mac(rawmac);
		if (mac != null)
			result[mac] = name;
	}

	return result;
}

/* ==================================================================== */
/*  Discovery helpers                                                   */
/* ==================================================================== */

function get_br_lan_broadcast() {
	let out = run('ip -4 addr show br-lan 2>/dev/null');
	if (out == '')
		return null;

	let lines = split(out, '\n');

	for (let i = 0; i < length(lines); i++) {
		let f = tokenize(lines[i]);
		for (let j = 0; j < length(f) - 1; j++)
			if (f[j] == 'brd')
				return f[j + 1];
	}

	for (let i = 0; i < length(lines); i++) {
		let f = tokenize(lines[i]);
		for (let j = 0; j < length(f) - 1; j++) {
			if (f[j] != 'inet')
				continue;

			let cidr = f[j + 1];
			let slash = index(cidr, '/');
			if (slash < 1)
				continue;

			let ip = substr(cidr, 0, slash);
			let prefix = int(substr(cidr, slash + 1));
			if (prefix < 0 || prefix > 32)
				continue;

			let block = 1;
			for (let k = 0; k < 32 - prefix; k++)
				block *= 2;

			let octets = split(ip, '.');
			if (length(octets) != 4)
				continue;

			let n = 0;
			for (let k = 0; k < 4; k++)
				n = n * 256 + int(octets[k]);

			let b = n - (n % block) + block - 1;

			return sprintf('%d.%d.%d.%d',
				int(b / 16777216) % 256,
				int(b / 65536) % 256,
				int(b / 256) % 256,
				b % 256);
		}
	}

	return null;
}

function ping_discover() {
	let bcast = get_br_lan_broadcast();
	if (bcast != null)
		run("ping -I br-lan -c 2 -W 1 '" + bcast + "' >/dev/null 2>&1");

	run('ping6 -I br-lan -c 2 -W 1 ff02::1 >/dev/null 2>&1 || ' +
	    'ping -I br-lan -c 2 -W 1 ff02::1 >/dev/null 2>&1');
}

/* ==================================================================== */
/*  Device collection                                                   */
/* ==================================================================== */

function collect_devices() {
	load_vendor_data();

	let devices = {};

	function ensure(mac) {
		if (devices[mac] == null)
			devices[mac] = {
				mac: mac,
				hostname: '',
				vendor: lookup_vendor(mac),
				online: false,
				ipv4: [],
				ipv6: []
			};
		return devices[mac];
	}

	let hints = null;
	let uout = run('ubus call luci-rpc getHostHints 2>/dev/null');
	if (uout != '') {
		try { hints = json(uout); }
		catch (e) { hints = null; }
	}

	if (hints != null) {
		for (let rawmac, info in hints) {
			let mac = norm_mac(rawmac);
			if (mac == null)
				continue;

			let d = ensure(mac);

			if (info.name != null && info.name != '')
				d.hostname = info.name;

			if (info.ipaddrs != null)
				for (let i = 0; i < length(info.ipaddrs); i++)
					push_unique(d.ipv4, info.ipaddrs[i]);

			if (info.ip6addrs != null)
				for (let i = 0; i < length(info.ip6addrs); i++)
					push_unique(d.ipv6, info.ip6addrs[i]);
		}
	}

	for (let mac, info in parse_arp()) {
		let d = ensure(mac);
		if (info.online)
			d.online = true;
		for (let i = 0; i < length(info.ips); i++)
			push_unique(d.ipv4, info.ips[i]);
	}

	for (let mac, info in parse_nd6()) {
		let d = ensure(mac);
		if (info.online)
			d.online = true;
		for (let i = 0; i < length(info.ips); i++)
			push_unique(d.ipv6, info.ips[i]);
	}

	for (let mac, name in parse_leases()) {
		if (devices[mac] != null &&
		    (devices[mac].hostname == null || devices[mac].hostname == ''))
			devices[mac].hostname = name;
	}

	let list = [];
	for (let mac, d in devices)
		push(list, d);

	for (let i = 1; i < length(list); i++) {
		let key = list[i];
		let j = i - 1;
		while (j >= 0 && list[j].mac > key.mac) {
			list[j + 1] = list[j];
			j--;
		}
		list[j + 1] = key;
	}

	return list;
}

/* ==================================================================== */
/*  rpcd protocol                                                       */
/* ==================================================================== */

let methods = {
	data: function() {
		return { devices: collect_devices() };
	},

	refresh: function() {
		ping_discover();
		return { devices: collect_devices() };
	},

	clear: function() {
		run('ip neigh flush all >/dev/null 2>&1');
		run('ip -6 neigh flush all >/dev/null 2>&1');
		ping_discover();
		return { devices: collect_devices() };
	}
};

let op = ARGV[0];

if (op == 'list') {
	let desc = {};
	for (let name, fn in methods)
		desc[name] = {};
	printf('%J\n', desc);
}
else if (methods[op] != null) {
	let args = {};
	let input = null;

	try { input = readfile('/dev/stdin'); }
	catch (e) { input = null; }

	if (input != null && length(trim(input)) > 0) {
		try { args = json(input); }
		catch (e) { args = {}; }
	}

	let res = methods[op](args);
	printf('%J\n', res);
}
else {
	exit(1);
}