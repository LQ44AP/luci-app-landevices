'use strict';
'require view';
'require poll';
'require rpc';
'require ui';

var callData = rpc.declare({
	object: 'landevices',
	method: 'data'
});

var callRefresh = rpc.declare({
	object: 'landevices',
	method: 'refresh'
});

var callClear = rpc.declare({
	object: 'landevices',
	method: 'clear'
});

return view.extend({

	/* ------------------------------------------------------------------ */
	/* Render helpers                                                      */
	/* ------------------------------------------------------------------ */

	_statusLabel: function (online) {
		var span = document.createElement('span');
		span.className = online ? 'label success' : 'label danger';
		span.textContent = online ? 'Online' : 'Offline';
		return span;
	},

	_renderTable: function (data, onlineOnly) {
		var table = document.getElementById('landevices-table');
		if (!table) return;

		var tbody = table.querySelector('tbody');
		while (tbody.firstChild) tbody.removeChild(tbody.firstChild);

		var total = 0, online = 0, visIdx = 0;

		data.forEach(function (dev) {
			total++;
			if (dev.online) online++;

			if (onlineOnly && !dev.online) return;

			var rowClass = (visIdx++ % 2) ? 'ld-row-odd' : 'ld-row-even';

			var ipv4 = dev.ipv4 && dev.ipv4.length ? dev.ipv4 : [''];
			var ipv6 = dev.ipv6 && dev.ipv6.length ? dev.ipv6 : [''];
			var rows = ipv4.length;

			for (var i = 0; i < rows; i++) {
				var tr = document.createElement('tr');
				tr.className = 'tr ' + rowClass;

				if (i === 0) {
					var tdMac = document.createElement('td');
					tdMac.className = 'td';
					tdMac.textContent = dev.mac;
					if (rows > 1) tdMac.rowSpan = rows;
					tr.appendChild(tdMac);

					var tdHost = document.createElement('td');
					tdHost.className = 'td';
					tdHost.textContent = dev.hostname || '-';
					if (rows > 1) tdHost.rowSpan = rows;
					tr.appendChild(tdHost);

					var tdVendor = document.createElement('td');
					tdVendor.className = 'td';
					tdVendor.textContent = dev.vendor || 'Unknown';
					tdVendor.style.fontStyle = 'italic';
					tdVendor.style.color = '#909090';
					if (rows > 1) tdVendor.rowSpan = rows;
					tr.appendChild(tdVendor);

					var tdStatus = document.createElement('td');
					tdStatus.className = 'td';
					tdStatus.appendChild(this._statusLabel(dev.online));
					if (rows > 1) tdStatus.rowSpan = rows;
					tr.appendChild(tdStatus);
				}

				var td4 = document.createElement('td');
				td4.className = 'td';
				td4.textContent = ipv4[i] || '';
				tr.appendChild(td4);

				if (i === 0) {
					var td6 = document.createElement('td');
					td6.className = 'td';
					if (rows > 1) td6.rowSpan = rows;
					ipv6.forEach(function (ip, idx) {
						if (idx > 0) td6.appendChild(document.createElement('br'));
						td6.appendChild(document.createTextNode(ip));
					});
					tr.appendChild(td6);
				}

				tbody.appendChild(tr);
			}
		}.bind(this));

		var counter = document.getElementById('landevices-counter');
		if (counter)
			counter.textContent = 'Total: ' + total + ' / Online: ' + online;
	},

	/* ------------------------------------------------------------------ */
	/* Data fetcher                                                        */
	/* ------------------------------------------------------------------ */

	_fetchData: function () {
		return callData().then(function (res) {
			return res.devices || [];
		}).catch(function () {
			return [];
		});
	},

	/* ------------------------------------------------------------------ */
	/* View lifecycle                                                      */
	/* ------------------------------------------------------------------ */

	load: function () {
		return this._fetchData();
	},

	render: function (data) {
		var self = this;

		var header = E('div', { 'class': 'cbi-section' }, [
			E('style', {}, [
				'.cbi-page-actions { display: none !important; }',
				'#landevices-table tbody tr.ld-row-even { background-color: #ffffff; }',
				'#landevices-table tbody tr.ld-row-odd  { background-color: #f4f8fa; }',
				'#landevices-table tbody tr.ld-row-odd:hover,',
				'#landevices-table tbody tr.ld-row-even:hover { background-color: #eef5fb; }',
				'@keyframes ld-spin { to { transform: rotate(360deg); } }',
				'.ld-spinner { display: inline-block; width: 12px; height: 12px;',
				'  border: 2px solid rgba(255,255,255,0.4); border-top-color: #fff;',
				'  border-radius: 50%; animation: ld-spin 0.7s linear infinite;',
				'  vertical-align: -2px; margin-right: 6px; }'
			].join('\n')),

			E('h2', {}, 'LAN Devices'),

			E('div', {
				'class': 'cbi-section-node',
				'style': 'display:flex; align-items:center; gap:12px; margin-bottom:10px;'
			}, [
				E('span', {
					id: 'landevices-counter',
					'style': 'font-weight:bold; margin-right:auto;'
				}, 'Total: 0 / Online: 0'),

				E('label', { 'style': 'display:inline-flex; align-items:center; gap:4px; cursor:pointer;' }, [
					E('input', {
						id: 'landevices-online-only',
						type: 'checkbox',
						checked: 'checked',
						'change': function () { self._rerender(); }
					}),
					' Online only'
				]),

				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'id': 'landevices-btn-refresh',
					'click': function () { self._refresh(); }
				}, 'Refresh'),

				E('button', {
					'class': 'btn cbi-button cbi-button-negative',
					'id': 'landevices-btn-clear',
					'click': function () { self._clear(); }
				}, 'Clear')
			]),

			E('table', {
				id: 'landevices-table',
				'class': 'table cbi-section-table'
			}, [
				E('thead', {}, E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, 'MAC Address'),
					E('th', { 'class': 'th' }, 'Hostname'),
					E('th', { 'class': 'th' }, 'Vendor'),
					E('th', { 'class': 'th' }, 'Status'),
					E('th', { 'class': 'th' }, 'IPv4 Address'),
					E('th', { 'class': 'th' }, 'IPv6 Address')
				])),
				E('tbody', { 'class': 'tbody' })
			])
		]);

		if (Array.isArray(data) && data.length) {
			var cb = document.getElementById('landevices-online-only');
			this._renderTable(data, cb ? cb.checked : true);
		}

		poll.add(L.bind(function () {
			return this._fetchData().then(L.bind(function (devices) {
				var cb = document.getElementById('landevices-online-only');
				this._renderTable(devices, cb ? cb.checked : true);
			}, this));
		}, this), 30);

		return header;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	_refresh: function () {
		return this._action('refresh', callRefresh);
	},

	_clear: function () {
		return this._action('clear', callClear);
	},

	_setButtonLoading: function (btn, loading) {
		if (!btn) return;

		if (loading) {
			if (btn.dataset.label == null)
				btn.dataset.label = btn.textContent;
			btn.disabled = true;
			btn.textContent = '';
			btn.appendChild(E('span', { 'class': 'ld-spinner' }));
			btn.appendChild(document.createTextNode('Loading\u2026'));
		} else {
			btn.textContent = btn.dataset.label != null ? btn.dataset.label : '';
			btn.disabled = false;
		}
	},

	_action: function (name, rpcFn) {
		var self = this,
		    btn = document.getElementById('landevices-btn-' + name);

		this._setButtonLoading(btn, true);

		return rpcFn().then(function (res) {
			var devices = res.devices || [];
			var cb = document.getElementById('landevices-online-only');
			self._renderTable(devices, cb ? cb.checked : true);
		}).catch(function (e) {
			ui.addNotification(null,
				E('p', {}, 'Action failed: ' + (e.message || e)));
		}).then(function () {
			self._setButtonLoading(btn, false);
		});
	},

	_rerender: function () {
		var self = this;
		this._fetchData().then(function (devices) {
			var cb = document.getElementById('landevices-online-only');
			self._renderTable(devices, cb ? cb.checked : true);
		});
	}
});