function extractTongjiNotices() {
  if (location.origin !== 'https://1.tongji.edu.cn' || location.pathname !== '/workbench') throw new Error('仅支持 https://1.tongji.edu.cn/workbench');
  // Find the exact announcement label; never serialize the whole page or read forms.
  const labels = [...document.querySelectorAll('h1,h2,h3,h4,span,div,p')].filter(e => e.children.length === 0 && e.textContent.trim() === '通知公告');
  let list = null;
  for (const label of labels) {
    let parent=label.parentElement;
    for(let depth=0; parent && depth<4 && !list; depth++,parent=parent.parentElement) {
      const lists=[...parent.querySelectorAll('ul,ol,[role="list"]')];
      if(lists.length===1) list=lists[0];
      else if(lists.length>1) break; // Ambiguous page structure: stop, never scan other sections.
    }
    if(list)break;
  }
  if(!list)throw new Error('未找到独立公告列表，请确认已登录且页面加载完成。');
  const rows=[...list.querySelectorAll('li,[role="listitem"]')];
  const notices=[];const seen=new Set();
  for(const row of rows.slice(0,100)) {
    const text=row.innerText.trim();
    const m=text.match(/^(.*?)\s*(20\d{2}-\d{2}-\d{2})(?:\s+\d{2}:\d{2}:\d{2})?\s*$/s);
    if(!m)continue;
    const title=m[1].replace(/\s+/g,' ').trim();
    if(title.length<5||title.length>400)continue;
    const key=title+'|'+m[2];if(seen.has(key))continue;seen.add(key);
    notices.push({title,date:m[2],pinned:false});
  }
  if(!notices.length)throw new Error('没有识别到标题和日期；没有导出其他内容。');
  return {schemaVersion:1,source:'https://1.tongji.edu.cn/workbench',exportedAt:new Date().toISOString(),notices};
}
