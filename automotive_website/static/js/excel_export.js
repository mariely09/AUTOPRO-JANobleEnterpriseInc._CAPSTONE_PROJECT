// ── Shared styled Excel export helper ──────────────────────────────────────
// Mirrors the print layout header (ap-header-left / ap-header-right split).
// Usage:
//   _downloadExcel(filename, reportTitle, headers, rows, footer, opts)
//
// Parameters:
//   filename     – e.g. 'Item_Master_2026-07-04.xlsx'
//   reportTitle  – shown right-aligned in the header block
//   headers      – array of column name strings
//   rows         – array of arrays (one per data row)
//   footer       – optional { values: [ {value, colIndex(1-based)} | plain ] }
//   opts         – optional { descColIndex: <0-based col index> }
//                  descColIndex: column whose value may contain \n → rich-text two-line cell
//
// Requires ExcelJS loaded on the page before calling.
// ──────────────────────────────────────────────────────────────────────────

async function _downloadExcel(filename, reportTitle, headers, rows, footer, opts) {
  var ExcelJS = window.ExcelJS;
  if (!ExcelJS) { alert('ExcelJS not loaded yet, please try again.'); return; }

  var wb = new ExcelJS.Workbook();
  wb.creator = 'Caltex AutoPro';
  wb.created = new Date();
  var ws = wb.addWorksheet('Report', {
    pageSetup: { orientation: 'landscape', fitToPage: true, fitToWidth: 1 }
  });

  var now      = new Date();
  var dateStr  = now.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
  var timeStr  = now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
  var colCount = headers.length;

  // ── Colours (match print layout) ──
  var RED   = 'FFE8001C';
  var DARK  = 'FF1A202C';
  var STRIPE = 'FFF8FAFC';
  var GREY  = 'FF718096';
  var LGREY = 'FFA0AEC0';

  // Left half = company block, right half = report info
  var leftCols   = Math.ceil(colCount / 2);
  var rightStart = leftCols + 1;

  // ── Row 1: company name | "OFFICIAL REPORT" label ──
  ws.mergeCells(1, 1,          1, leftCols);
  ws.mergeCells(1, rightStart, 1, colCount);
  var r1L = ws.getCell(1, 1);
  r1L.value     = 'JA Noble Enterprise Inc.';
  r1L.font      = { name: 'Segoe UI', size: 14, bold: true, color: { argb: DARK } };
  r1L.alignment = { vertical: 'middle', horizontal: 'left' };
  ws.getRow(1).height = 22;
  var r1R = ws.getCell(1, rightStart);
  r1R.value     = 'OFFICIAL REPORT';
  r1R.font      = { name: 'Segoe UI', size: 7, bold: true, color: { argb: LGREY } };
  r1R.alignment = { vertical: 'middle', horizontal: 'right' };

  // ── Row 2: branch | report title ──
  ws.mergeCells(2, 1,          2, leftCols);
  ws.mergeCells(2, rightStart, 2, colCount);
  var r2L = ws.getCell(2, 1);
  r2L.value     = 'Caltex San Pedro';
  r2L.font      = { name: 'Segoe UI', size: 9, bold: true, color: { argb: GREY } };
  r2L.alignment = { vertical: 'middle', horizontal: 'left' };
  ws.getRow(2).height = 18;
  var r2R = ws.getCell(2, rightStart);
  r2R.value     = reportTitle;
  r2R.font      = { name: 'Segoe UI', size: 13, bold: true, color: { argb: DARK } };
  r2R.alignment = { vertical: 'middle', horizontal: 'right' };

  // ── Row 3: address | date range + "Generated on …" meta ──
  ws.mergeCells(3, 1,          3, leftCols);
  ws.mergeCells(3, rightStart, 3, colCount);
  var r3L = ws.getCell(3, 1);
  r3L.value     = '102 National Highway, Brgy. Landayan, San Pedro, Laguna';
  r3L.font      = { name: 'Segoe UI', size: 8, color: { argb: LGREY } };
  r3L.alignment = { vertical: 'middle', horizontal: 'left' };
  ws.getRow(3).height = 14;
  var r3R = ws.getCell(3, rightStart);
  var excelDateRange = (opts && opts.dateRange) || '';
  if (excelDateRange) {
    r3R.value = { richText: [
      { text: 'Date Range: ',  font: { name: 'Segoe UI', size: 8, color: { argb: GREY } } },
      { text: excelDateRange,  font: { name: 'Segoe UI', size: 8, bold: true, color: { argb: DARK } } }
    ]};
  }
  r3R.alignment = { vertical: 'middle', horizontal: 'right' };

  // ── Row 4: generated date ──
  ws.mergeCells(4, 1,          4, leftCols);
  ws.mergeCells(4, rightStart, 4, colCount);
  ws.getRow(4).height = 13;
  var r4R = ws.getCell(4, rightStart);
  r4R.value     = 'Generated on ' + dateStr + ' at ' + timeStr;
  r4R.font      = { name: 'Segoe UI', size: 8, color: { argb: GREY } };
  r4R.alignment = { vertical: 'middle', horizontal: 'right' };

  // ── Row 5: blank spacer ──
  ws.addRow([]);
  ws.getRow(5).height = 6;

  // ── Row 6: column headers — black fill, white bold caps ──
  var headerRow = ws.addRow(headers);
  headerRow.height = 18;
  headerRow.eachCell(function(cell) {
    cell.value     = (cell.value || '').toString().toUpperCase();
    cell.fill      = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF000000' } };
    cell.font      = { name: 'Segoe UI', size: 8, bold: true, color: { argb: 'FFFFFFFF' } };
    cell.alignment = { vertical: 'middle', horizontal: 'left', wrapText: false };
  });

  // ── Data rows ──
  var descColIdx = (opts && opts.descColIndex !== undefined) ? opts.descColIndex : -1;

  rows.forEach(function(rowData, idx) {
    var hasTwoLines = descColIdx >= 0 && String(rowData[descColIdx] || '').indexOf('\n') !== -1;

    var cleaned = rowData.map(function(v, ci) {
      var s = String(v === null || v === undefined ? '' : v)
                .replace(/<br\s*\/?>/gi, '\n')
                .replace(/<[^>]+>/g, '')
                .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
      if (ci !== descColIdx) {
        var n = parseFloat(s.replace(/[₱,]/g, ''));
        if (!isNaN(n) && s.replace(/[₱,\s]/g, '') !== '' && !/[a-zA-Z]/.test(s.replace(/₱/g, ''))) return n;
      }
      return s;
    });

    var dr = ws.addRow(cleaned);
    dr.height = hasTwoLines ? 28 : 15;
    var isEven = idx % 2 === 1;

    dr.eachCell({ includeEmpty: true }, function(cell, colNum) {
      var colIdx0 = colNum - 1;
      if (isEven) {
        cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: STRIPE } };
      }
      cell.border = { bottom: { style: 'hair', color: { argb: 'FFF0F4F8' } } };

      if (colIdx0 === descColIdx && hasTwoLines) {
        var lines = String(cleaned[descColIdx] || '').split('\n');
        cell.value = { richText: [
          { text: lines[0],              font: { name: 'Segoe UI', size: 8.5, bold: true,  color: { argb: 'FF1A202C' } } },
          { text: '\n' + (lines[1]||''), font: { name: 'Segoe UI', size: 7.5, bold: false, color: { argb: GREY } } }
        ]};
        cell.alignment = { vertical: 'top', wrapText: true };
      } else {
        cell.font      = { name: 'Segoe UI', size: 8.5, color: { argb: 'FF2D3748' } };
        cell.alignment = { vertical: 'middle', wrapText: false };
      }
    });
  });

  // ── Totals row ──
  // footer.values: [ { value, colIndex(1-based) } ]  OR  plain values placed at end
  if (footer && footer.values && footer.values.length) {
    ws.addRow([]);
    var totalCells = new Array(colCount).fill('');

    if (typeof footer.values[0] === 'object' && footer.values[0] !== null && 'colIndex' in footer.values[0]) {
      footer.values.forEach(function(v) { totalCells[v.colIndex - 1] = v.value; });
      var firstIdx = footer.values[0].colIndex - 1;
      if (firstIdx > 0) totalCells[firstIdx - 1] = 'TOTAL';
    } else {
      var insertAt = colCount - footer.values.length;
      footer.values.forEach(function(v, i) { totalCells[insertAt + i] = v; });
      if (insertAt > 0) totalCells[insertAt - 1] = 'TOTAL';
    }

    var totRow = ws.addRow(totalCells);
    totRow.height = 16;
    totRow.eachCell({ includeEmpty: true }, function(cell) {
      cell.font   = { name: 'Segoe UI', size: 9, bold: true, color: { argb: 'FFFFFFFF' } };
      cell.fill   = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF000000' } };
    });
  }

  // ── Auto column widths (capped at 40 chars) ──
  var colWidths = headers.map(function(h) { return Math.max(String(h).length, 8); });
  rows.forEach(function(rowData) {
    rowData.forEach(function(v, i) {
      var s = String(v || '').replace(/<[^>]+>/g, '').split('\n')[0]; // first line only
      if (s.length > colWidths[i]) colWidths[i] = s.length;
    });
  });
  colWidths.forEach(function(w, i) {
    ws.getColumn(i + 1).width = Math.min(w + 4, 40);
  });

  // ── Download ──
  var buf  = await wb.xlsx.writeBuffer();
  var blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  var url  = URL.createObjectURL(blob);
  var a    = document.createElement('a');
  a.href     = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
