let blobURL;
document.getElementById('read').addEventListener('click',async()=>{
  const button=document.getElementById('read'),status=document.getElementById('status'),link=document.getElementById('download');
  button.disabled=true;link.hidden=true;
  if(blobURL){URL.revokeObjectURL(blobURL);blobURL=null;}
  try{
    const [tab]=await chrome.tabs.query({active:true,currentWindow:true});
    if(!tab?.url)throw new Error('请切换到同济工作台。');
    const url=new URL(tab.url);
    if(url.origin!=='https://1.tongji.edu.cn'||url.pathname!=='/workbench')throw new Error('仅支持同济工作台，其他页面不会读取。');
    const results=await chrome.scripting.executeScript({target:{tabId:tab.id,frameIds:[0]},func:extractTongjiNotices});
    const data=results[0]?.result;
    if(!data?.notices?.length)throw new Error('未读到公告。');
    blobURL=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));
    link.href=blobURL;link.download='tongji-news-'+new Date().toISOString().slice(0,10)+'.json';link.hidden=false;
    status.textContent='已读取 '+data.notices.length+' 条标题和日期。点击下方保存，再在桌宠中选择“导入 JSON”。';
  }catch(e){status.textContent=e.message || '读取失败，请确认已登录。';}
  finally{button.disabled=false;}
});
