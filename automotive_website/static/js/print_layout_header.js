// ── Shared print engine — CSS @media print overlay, zero navigation ──
// summary: array of { label, value, color } — rendered as a compact stats strip below the red divider
// footer (optional): { columns: [...], values: [...] } — renders a totals row at the bottom of the table
// options (optional): { dateRange: 'June 1, 2026 – July 1, 2026' } — shown below report title, above Generated on
function _doPrint(title, summary, columns, rows, footer, options) {
  var now = new Date();
  var dateStr = now.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
  var timeStr = now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });

  // ── Extract & format date range from title if present ──
  // Pattern: " · 2026-06-01 to 2026-07-01" — strip from title and format nicely
  var dateRange = (options && options.dateRange) || '';
  var cleanTitle = title;
  var isoRangeMatch = title.match(/\s*[·•]\s*(\d{4}-\d{2}-\d{2})\s+to\s+(\d{4}-\d{2}-\d{2})/);
  if (isoRangeMatch && !dateRange) {
    function _fmtIsoDate(iso) {
      var FULL_MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      var p = iso.match(/^(\d{4})-(\d{2})-(\d{2})$/);
      if (!p) return iso;
      return FULL_MONTHS[parseInt(p[2])-1] + ' ' + parseInt(p[3]) + ', ' + p[1];
    }
    dateRange = _fmtIsoDate(isoRangeMatch[1]) + ' – ' + _fmtIsoDate(isoRangeMatch[2]);
    cleanTitle = title.replace(isoRangeMatch[0], '').trim();
  }

  var dateRangeHtml = dateRange
    ? '<div class="ap-report-daterange">Date Range: <strong>' + dateRange + '</strong></div>'
    : '';

  // Summary strip intentionally omitted from print layout

  // Build table header with proportional col widths if provided
  var colWidths = (options && options.colWidths) || [];
  var colGroupHtml = '';
  if (colWidths.length === (columns||[]).length) {
    var wSum = colWidths.reduce(function(a,b){ return a+b; }, 0);
    colGroupHtml = '<colgroup>'
      + colWidths.map(function(w){ return '<col style="width:' + (w/wSum*100).toFixed(2) + '%">'; }).join('')
      + '</colgroup>';
  }

  var theadHtml = (columns||[]).map(function(c) { return '<th>' + c + '</th>'; }).join('');
  var tbodyHtml = '';
  if (!rows || rows.length === 0) {
    tbodyHtml = '<tr><td colspan="' + (columns||[]).length + '" style="text-align:center;padding:2rem 1rem;color:#718096;font-size:9px;font-style:italic;">No records found for the selected filters.</td></tr>';
  } else {
    tbodyHtml = rows.map(function(row, idx) {
      return '<tr class="' + (idx%2===1?'even':'') + '">'
        + row.map(function(cell){ return '<td>' + cell + '</td>'; }).join('')
        + '</tr>';
    }).join('');
  }

  // Build footer/totals row if provided — dark bg, white bold text, matches PDF totals row
  var tfootHtml = '';
  if (footer && footer.values) {
    var colCount = columns.length;
    var colSpan = colCount - footer.values.length;
    tfootHtml = '<div class="ap-total-bar">'
      + '<table style="width:100%;border-collapse:collapse;font-size:8.5px;table-layout:fixed;">'
      + (colGroupHtml ? colGroupHtml : '')
      + '<tr>'
      + '<td colspan="' + colSpan + '" class="ap-total-label">TOTAL</td>'
      + footer.values.map(function(v){ return '<td class="ap-total-cell">' + (v !== null && v !== undefined ? v : '') + '</td>'; }).join('')
      + '</tr></table></div>';
  }

  // Build the full print content div
  var printDiv = document.createElement('div');
  printDiv.id = '_apPrintContent';
  printDiv.innerHTML =
    '<div class="ap-header">'
    +   '<div class="ap-header-inner">'
    +     '<div class="ap-header-left">'
    +       '<img src="/static/img/LOGO_CALTEX.png" class="ap-logo" alt="Caltex" onerror="this.style.display=\'none\'">'
    +       '<div class="ap-brand-block">'
    +         '<div class="ap-brand">JA Noble Enterprise Inc.</div>'
    +         '<div class="ap-brand-sub">Caltex San Pedro</div>'
    +         '<div class="ap-brand-address">102 National Highway, Brgy. Landayan, San Pedro, Laguna</div>'
    +       '</div>'
    +     '</div>'
    +     '<div class="ap-header-right">'
    +       '<div class="ap-report-label">Official Report</div>'
    +       '<div class="ap-report-title">' + cleanTitle + '</div>'
    +       dateRangeHtml
    +       '<div class="ap-report-meta">Generated on <strong>' + dateStr + '</strong> at ' + timeStr + '</div>'
    +     '</div>'
    +   '</div>'
    + '</div>'
    + '<div class="ap-content">'
    +   '<div class="ap-table-wrap"><table>' + colGroupHtml + '<thead><tr>' + theadHtml + '</tr></thead><tbody>' + tbodyHtml + '</tbody></table></div>'
    +   tfootHtml
    + '</div>'
    + '<div class="ap-print-footer">Caltex San Pedro &middot; JA Noble Enterprise Inc.</div>';

  // Inject print styles
  var styleEl = document.createElement('style');
  styleEl.id = '_apPrintStyle';
  styleEl.textContent = [
    '@media print {',
    '  body > *:not(#_apPrintContent) { display: none !important; }',
    '  #_apPrintContent { display: block !important; }',
    '  @page { size: landscape; margin: 8mm; }',
    '}',
    '* { box-sizing: border-box; margin: 0; padding: 0; }',
    '#_apPrintContent {',
    '  display: none;',
    '  font-family: "Segoe UI", Arial, sans-serif;',
    '  font-size: 10px;',
    '  color: #1a202c;',
    '  background: white;',
    '  width: 100%;',
    '  -webkit-print-color-adjust: exact !important;',
    '  print-color-adjust: exact !important;',
    '}',
    /* ── Header ── */
    '.ap-header { background: white; margin-bottom: 0; }',
    '.ap-header-inner {',
    '  display: flex; align-items: center; justify-content: space-between;',
    '  padding: 12px 0 10px;',
    '}',
    '.ap-header-left { display: flex; align-items: center; gap: 10px; }',
    '.ap-logo { width: 42px; height: 42px; object-fit: contain; flex-shrink: 0; }',
    '.ap-brand { font-size: 16px; font-weight: 900; color: #1a202c !important; letter-spacing: -0.3px; line-height: 1.1; }',
    '.ap-brand-sub { font-size: 6.5px; color: #718096 !important; font-weight: 700; letter-spacing: 1.8px; text-transform: uppercase; margin-top: 3px; }',
    '.ap-brand-address { font-size: 6.5px; color: #a0aec0 !important; font-weight: 400; margin-top: 2px; }',
    '.ap-header-right { text-align: right; }',
    '.ap-report-label { font-size: 6.5px; color: #a0aec0 !important; font-weight: 700; letter-spacing: 2px; text-transform: uppercase; margin-bottom: 3px; }',
    '.ap-report-title { font-size: 15px; font-weight: 800; color: #1a202c !important; line-height: 1.2; }',
    '.ap-report-meta { font-size: 7.5px; color: #718096 !important; margin-top: 3px; }',
    '.ap-report-meta strong { color: #1a202c !important; }',
    '.ap-report-daterange { font-size: 7.5px; color: #718096 !important; margin-top: 2px; margin-bottom: 1px; }',
    '.ap-report-daterange strong { color: #1a202c !important; }',
    /* ── Red divider rule (matches PDF HRFlowable) ── */
    '.ap-header-rule {',
    '  height: 2px;',
    '  background: #E8001C !important;',
    '  -webkit-print-color-adjust: exact !important;',
    '  print-color-adjust: exact !important;',
    '  margin-bottom: 0;',
    '}',
    /* ── Content area ── */
    '.ap-content { padding: 10px 0 0; }',
    '.ap-table-wrap { border-radius: 5px; overflow: hidden; border: 1px solid #e2e8f0; width: 100%; }',
    'table { width: 100%; border-collapse: collapse; font-size: 8.5px; table-layout: fixed; }',
    /* ── Table header row — dark bg, white text ── */
    'thead tr {',
    '  background: #000000 !important;',
    '  -webkit-print-color-adjust: exact !important;',
    '  print-color-adjust: exact !important;',
    '}',
    'thead th {',
    '  padding: 8px 6px; text-align: left;',
    '  font-size: 7px; font-weight: 700;',
    '  color: rgba(255,255,255,0.92) !important;',
    '  text-transform: uppercase; letter-spacing: 0.4px;',
    '  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;',
    '}',
    /* ── Table data rows — alternating stripe ── */
    'tbody tr { border-bottom: 1px solid #f0f4f8; }',
    'tbody tr.even {',
    '  background: #f8fafc !important;',
    '  -webkit-print-color-adjust: exact !important;',
    '  print-color-adjust: exact !important;',
    '}',
    'tbody td {',
    '  padding: 5px 6px; vertical-align: middle;',
    '  color: #2d3748 !important; line-height: 1.3;',
    '  font-size: 8.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;',
    '}',
    /* Allow description-like columns (2nd and 4th) to wrap */
    'tbody td:nth-child(2) { white-space: normal; overflow: visible; text-overflow: clip; }',
    'tbody td:nth-child(4) { white-space: normal; overflow: visible; text-overflow: clip; }',
    /* ── Totals row — dark bg, white bold text (matches PDF totals row) ── */
    '.ap-total-bar { margin-top: 0; }',
    '.ap-total-bar table { border-radius: 0 0 5px 5px; overflow: hidden; }',
    '.ap-total-label {',
    '  text-align: right; font-weight: 800; font-size: 8.5px;',
    '  padding: 7px 6px;',
    '  background: #1a202c !important; color: rgba(255,255,255,0.9) !important;',
    '  -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important;',
    '}',
    '.ap-total-cell {',
    '  font-weight: 800; font-size: 8.5px;',
    '  padding: 7px 6px;',
    '  background: #1a202c !important; color: rgba(255,255,255,0.9) !important;',
    '  -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important;',
    '}',
    /* ── Badges ── */
    '.badge { display: inline-block; padding: 2px 6px; border-radius: 20px; font-size: 7.5px; font-weight: 700; }',
    '.badge-in {',
    '  background: #ebf8ff !important; color: #003087 !important;',
    '  border: 1px solid #bee3f8;',
    '  -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important;',
    '}',
    '.badge-out {',
    '  background: #fff5f5 !important; color: #E8001C !important;',
    '  border: 1px solid #fed7d7;',
    '  -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important;',
    '}',
    /* ── Footer ── */
    '.ap-print-footer {',
    '  margin-top: 16px; padding-top: 8px;',
    '  border-top: 1px solid #e2e8f0;',
    '  text-align: center;',
    '  font-size: 7px;',
    '  color: #a0aec0 !important;',
    '  font-weight: 500;',
    '  letter-spacing: 0.5px;',
    '}',
  ].join('\n');

  document.head.appendChild(styleEl);
  document.body.appendChild(printDiv);

  // Print then clean up
  setTimeout(function() {
    window.print();
    setTimeout(function() {
      var s = document.getElementById('_apPrintStyle');
      var d = document.getElementById('_apPrintContent');
      if (s) s.remove();
      if (d) d.remove();
    }, 500);
  }, 100);
}
