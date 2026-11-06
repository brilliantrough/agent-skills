import React, { useEffect, useRef } from 'react';
import templates from './templates.json';

const GOLD = '#E2C98F', BLUE = '#83BED9', LINE = '#579AB9';
const position = (x, y, width, height) => ({ position: 'absolute', left: x, top: y, width, height });

function Copy({ name, value, style, ...attributes }) {
  return <div data-editable-path={name} style={{ margin: 0, whiteSpace: 'pre-wrap', lineHeight: 1.3, ...style }} {...attributes}>{value}</div>;
}

function Chart({ props, combo }) {
  const ref = useRef(null);
  const count = props.categoryCount, series = props.seriesCount;
  useEffect(() => {
    const root = ref.current;
    function update() {
      const nodes = [...root.querySelectorAll('[data-nju-value]')];
      const values = nodes.map(node => node.textContent.trim() === '' ? NaN : Number(node.textContent.trim()));
      nodes.forEach((node, i) => node.setAttribute('aria-invalid', String(!Number.isFinite(values[i]))));
      if (values.some(value => !Number.isFinite(value))) return;
      const bars = values.filter((_, i) => !combo || Math.floor(i / count) === 0);
      const min = Math.min(0, ...bars), max = Math.max(0, ...bars);
      const range = max - min || 1;
      const y = value => 230 - (value - min) / range * 198;
      root.querySelector('[data-nju-axis]').setAttribute('y1', y(0));
      root.querySelector('[data-nju-axis]').setAttribute('y2', y(0));
      const lineValues = combo ? values.slice(count) : [];
      const lineMin = Math.min(0, ...lineValues), lineMax = Math.max(0, ...lineValues);
      const points = [];
      nodes.forEach((node, i) => {
        const s = Math.floor(i / count), c = i % count;
        const center = 72 + (c + .5) * 950 / count;
        const value = values[i];
        const top = combo && s === 1 ? 230 - (value - lineMin) / (lineMax - lineMin || 1) * 198 : y(value);
        const bar = root.querySelector(`[data-nju-bar="${s}-${c}"]`);
        if (bar) {
          bar.setAttribute('y', Math.min(y(0), top));
          bar.setAttribute('height', Math.abs(top - y(0)));
        }
        node.style.top = `${Math.max(2, top - 25)}px`;
        if (combo && s === 1) points.push(`${center},${top}`);
      });
      if (combo) root.querySelector('polyline').setAttribute('points', points.join(' '));
    }
    const observer = new MutationObserver(update);
    observer.observe(root, { subtree: true, childList: true, characterData: true });
    update();
    return () => observer.disconnect();
  }, [count, series, combo]);
  return <div ref={ref} style={{ ...position(96, 152, 1088, 304), fontSize: 17 }}>
    <svg viewBox="0 0 1088 304" style={position(0, 0, 1088, 304)} aria-label={combo ? '柱线图' : '柱状图'}>
      <line data-nju-axis="" x1="60" x2="1030" y1="230" y2="230" stroke="#D8EAF2" />
      {Array.from({ length: series }, (_, s) => Array.from({ length: count }, (_, c) => {
        const band = 950 / count, width = Math.min(72, band / (series + 1));
        const x = 76 + (c + .5) * band + (combo ? -.5 : s - series / 2) * width;
        return combo && s === 1 ? null : <rect key={`${s}-${c}`} data-nju-bar={`${s}-${c}`} x={x} width={width - 8} y="230" height="0" fill={[GOLD, BLUE, LINE][s]} />;
      }))}
      {combo && <polyline fill="none" stroke={LINE} strokeWidth="3" />}
    </svg>
    {Array.from({ length: series }, (_, s) => Array.from({ length: count }, (_, c) => {
      const band = 950 / count, width = Math.min(72, band / (series + 1));
      const center = 72 + (c + .5) * band + (combo ? 0 : (s - (series - 1) / 2) * width);
      const key = `CHART_VALUE_${s + 1}_${c + 1}`;
      return <Copy key={key} name={key} data-nju-value={`${s}-${c}`} value={props[key]} style={{ ...position(center - 42 + (combo && s === 1 ? 44 : 0), 0, 84, 25), textAlign: 'center', color: s === 1 && combo ? LINE : '#404040' }} />;
    }))}
    {Array.from({ length: count }, (_, c) => <Copy key={c} name={`CHART_CAT_${c + 1}`} value={props[`CHART_CAT_${c + 1}`]} style={{ ...position(72 + c * 950 / count, 240, 950 / count, 26), textAlign: 'center' }} />)}
    {Array.from({ length: series }, (_, s) => <div key={s} style={position(340 + s * 200, 278, 190, 24)}><span style={{ display: 'inline-block', width: 18, height: combo && s === 1 ? 3 : 10, background: [GOLD, combo ? LINE : BLUE, LINE][s], marginRight: 10 }} /><Copy name={`CHART_SERIES_${s + 1}`} value={props[`CHART_SERIES_${s + 1}`]} style={{ display: 'inline-block' }} /></div>)}
  </div>;
}

function Table({ props }) {
  const rows = props.rowCount, cols = props.columnCount;
  return <table style={{ ...position(96, 164, 1088, 260), borderCollapse: 'collapse', tableLayout: 'fixed', fontSize: 20, borderTop: `1.5px solid ${LINE}`, borderBottom: `1.5px solid ${LINE}` }}>
    <thead style={{ background: '#E4F3FA', color: '#56788B', borderBottom: `1px solid ${LINE}` }}><tr>{Array.from({ length: cols }, (_, c) => <th key={c} style={{ padding: '10px 14px', textAlign: c ? 'right' : 'left', fontWeight: 500 }}><Copy name={`TABLE_HEAD_${c + 1}`} value={props[`TABLE_HEAD_${c + 1}`]} /></th>)}</tr></thead>
    <tbody>{Array.from({ length: rows }, (_, r) => <tr key={r}>{Array.from({ length: cols }, (_, c) => <td key={c} style={{ padding: '8px 14px', textAlign: c ? 'right' : 'left' }}><Copy name={`TABLE_CELL_${r + 1}_${c + 1}`} value={props[`TABLE_CELL_${r + 1}_${c + 1}`]} /></td>)}</tr>)}</tbody>
  </table>;
}

export const pages = templates.map((template, index) => {
  const defaults = Object.fromEntries(template.fields.map(field => [field.key, '']));
  if (template.name.startsWith('chart_')) {
    Object.assign(defaults, { categoryCount: 3, seriesCount: template.name === 'chart_combo' ? 2 : 1 });
    for (let s = 1; s <= 3; s++) {
      defaults[`CHART_SERIES_${s}`] = '';
      for (let c = 1; c <= 6; c++) defaults[`CHART_VALUE_${s}_${c}`] = '0';
    }
    for (let c = 1; c <= 6; c++) defaults[`CHART_CAT_${c}`] = '';
  }
  if (template.name === 'table') {
    Object.assign(defaults, { rowCount: 4, columnCount: 4 });
    for (let c = 1; c <= 5; c++) {
      defaults[`TABLE_HEAD_${c}`] = '';
      for (let r = 1; r <= 6; r++) defaults[`TABLE_CELL_${r}_${c}`] = '';
    }
  }
  if (template.name === 'two_col') defaults.FIGURE_SRC = '';
  return { key: `nju_${template.name}`, themeKey: 'nju', pageNumber: index + 1, layout: `NJU-${template.name}`, slot: template.name, label: `南京大学 · ${template.name}`, bgClass: '', controls: [], defaultProps: defaults };
});

export const runtimePages = pages.map((page, index) => ({ ...page, Component: function NjuSlide(props) {
  const template = templates[index];
  return <div className="nju-slide" style={{ width: 1920, height: 1080, background: '#fff', position: 'relative', color: '#404040', fontFamily: '"Microsoft YaHei","PingFang SC",sans-serif' }}>
    <style>{'.nju-slide [data-nju-value][aria-invalid="true"]{outline:2px solid #b42318;color:#b42318!important}'}</style>
    <div style={{ ...position(0, 0, 1280, 720), transform: 'scale(1.5)', transformOrigin: 'top left', overflow: 'hidden' }}>
      {/* Only compiled, bundled SVG markup is inserted here; user copy is rendered as React text. */}
      <div aria-hidden="true" data-editable-skip="" style={position(0, 0, 1280, 720)} dangerouslySetInnerHTML={{ __html: template.backgroundSvg }} />
      {template.fields.map(field => <Copy key={field.key} name={field.key} value={props[field.key]} style={{ ...position(field.x, field.y, field.width, field.height), fontSize: field.size, fontWeight: field.weight, color: field.color, textAlign: field.align }} />)}
      {template.name.startsWith('chart_') && <Chart props={props} combo={template.name === 'chart_combo'} />}
      {template.name === 'table' && <Table props={props} />}
      {template.name === 'two_col' && props.FIGURE_SRC && <img src={props.FIGURE_SRC} alt={props.FIG_CAPTION || ''} data-editable-skip="" style={{ ...position(640, 164, 544, 272), objectFit: 'contain' }} />}
    </div>
  </div>;
} }));
