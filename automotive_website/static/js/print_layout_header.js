// ── Shared print engine — CSS @media print overlay, zero navigation ──
// footer (optional): { columns: [...], values: [...] } — renders a totals row at the bottom of the table
function _doPrint(title, summary, columns, rows, footer) {
  var now = new Date();
  var dateStr = now.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
  var timeStr = now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });

  // Build table rows
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

  // Build footer/totals row if provided
  var tfootHtml = '';
  if (footer && footer.values) {
    var colCount = columns.length;
    var colSpan = colCount - footer.values.length;
    tfootHtml = '<div class="ap-total-bar">'
      + '<table style="width:100%;border-collapse:collapse;font-size:8.5px;table-layout:fixed;"><tr>'
      + '<td colspan="' + colSpan + '" style="text-align:right;font-weight:800;font-size:9px;padding:8px 7px;border-top:2px solid #1a202c;">TOTAL</td>'
      + footer.values.map(function(v){ return '<td style="font-weight:800;font-size:9px;padding:8px 7px;border-top:2px solid #1a202c;">' + v + '</td>'; }).join('')
      + '</tr></table></div>';
  }

  // Build the full print content div
  var printDiv = document.createElement('div');
  printDiv.id = '_apPrintContent';
  printDiv.innerHTML =
    '<div class="ap-header">'
    +   '<div class="ap-header-inner">'
    +     '<div class="ap-header-left">'
    +       '<img src="/static/img/LOGO_CALTEX.png" class="ap-logo" alt="Caltex">'
    +       '<div class="ap-brand-block">'
    +         '<div class="ap-brand">JA Noble Enterprise Inc.</div>'
    +         '<div class="ap-brand-sub">Caltex San Pedro</div>'
    +         '<div class="ap-brand-address">102 National Highway, Brgy. Landayan, San Pedro, Laguna</div>'
    +       '</div>'
    +     '</div>'
    +     '<div class="ap-header-right">'
    +       '<div class="ap-report-label">Official Report</div>'
    +       '<div class="ap-report-title">' + title + '</div>'
    +       '<div class="ap-report-meta">Generated on <strong>' + dateStr + '</strong> at ' + timeStr + '</div>'
    +     '</div>'
    +   '</div>'
    + '</div>'
    + '<div class="ap-content">'
    +   '<div class="ap-table-wrap"><table><thead><tr>' + theadHtml + '</tr></thead><tbody>' + tbodyHtml + '</tbody></table></div>'
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
    '  @page { margin: 8mm; }',
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
    '.ap-header { background: white; margin-bottom: 0; }',
    '.ap-header-inner {',
    '  display: flex; align-items: center; justify-content: space-between;',
    '  padding: 14px 0 12px;',
    '}',
    '.ap-header-left { display: flex; align-items: center; gap: 12px; }',
    '.ap-logo { width: 44px; height: 44px; object-fit: contain; flex-shrink: 0; }',
    '.ap-brand-block {}',
    '.ap-brand { font-size: 18px; font-weight: 900; color: #1a202c !important; letter-spacing: -0.3px; line-height: 1; }',
    '.ap-brand span { color: #E8001C !important; }',
    '.ap-brand-sub { font-size: 7px; color: #718096 !important; font-weight: 600; letter-spacing: 1.8px; text-transform: uppercase; margin-top: 3px; }',
    '.ap-brand-address { font-size: 7px; color: #a0aec0 !important; font-weight: 500; margin-top: 2px; }',
    '.ap-header-right { text-align: right; }',
    '.ap-report-label { font-size: 7px; color: #a0aec0 !important; font-weight: 700; letter-spacing: 2px; text-transform: uppercase; margin-bottom: 2px; }',
    '.ap-report-title { font-size: 16px; font-weight: 800; color: #1a202c !important; line-height: 1.2; }',
    '.ap-report-meta { font-size: 8px; color: #718096 !important; margin-top: 3px; }',
    '.ap-report-meta strong { color: #1a202c !important; }',
    '.ap-header-rule {',
    '  height: 2px;',
    '  background: #E8001C !important;',
    '  -webkit-print-color-adjust: exact !important;',
    '  print-color-adjust: exact !important;',
    '  margin-bottom: 0;',
    '}',
    '.ap-strip {',
    '  display: flex; align-items: center;',
    '  padding: 5px 0;',
    '  border-bottom: 1px solid #e2e8f0;',
    '  margin-bottom: 14px;',
    '}',
    '.ap-strip-item { font-size: 8px; color: #718096 !important; }',
    '.ap-strip-item strong { color: #1a202c !important; font-weight: 700; }',
    '.ap-strip-sep { margin: 0 10px; color: #cbd5e0 !important; font-size: 10px; }',
    '.ap-content { padding: 14px 20px 0; }',
    '.ap-table-wrap { border-radius: 6px; overflow: hidden; border: 1.5px solid #e2e8f0; width: 100%; }',
    'table { width: 100%; border-collapse: collapse; font-size: 8.5px; table-layout: fixed; }',
    'thead tr {',
    '  background: #1a202c !important;',
    '  -webkit-print-color-adjust: exact !important;',
    '  print-color-adjust: exact !important;',
    '}',
    'thead th {',
    '  padding: 8px 7px; text-align: left;',
    '  font-size: 7px; font-weight: 700;',
    '  color: rgba(255,255,255,0.92) !important;',
    '  text-transform: uppercase; letter-spacing: 0.4px;',
    '  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;',
    '}',
    'tbody tr { border-bottom: 1px solid #f0f4f8; }',
    'tbody tr.even {',
    '  background: #f8fafc !important;',
    '  -webkit-print-color-adjust: exact !important;',
    '  print-color-adjust: exact !important;',
    '}',
    'tbody td { padding: 5px 7px; vertical-align: middle; color: #2d3748 !important; line-height: 1.3; font-size: 8.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }',
    'tbody td:nth-child(2) { white-space: normal; overflow: visible; text-overflow: clip; }',
    'tbody td:nth-child(4) { white-space: normal; overflow: visible; text-overflow: clip; }',
    '.badge { display: inline-block; padding: 2px 7px; border-radius: 20px; font-size: 8px; font-weight: 700; }',
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
    '.ap-print-footer {',
    '  margin-top: 18px; padding-top: 10px;',
    '  border-top: 1px solid #e2e8f0;',
    '  text-align: center;',
    '  font-size: 7.5px;',
    '  color: #a0aec0 !important;',
    '  font-weight: 500;',
    '  letter-spacing: 0.3px;',
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
