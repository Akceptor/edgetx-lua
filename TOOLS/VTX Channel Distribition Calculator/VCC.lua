-- TNS|Video Channel Calculator|TNE
-- FPV Video Channel Distribution Calculator

local ranges = { "A", "B", "E", "F", "R", "L" }
local includeXBand = false
local userSelected, calculated = {}, {}
local pilots = 2
local popupTimer, popupMsg = 0, nil

-- detect color screen (TX16S, TX15)
local COLOR = (LCD_W >= 320 and LCD_H >= 200)

----------------------------------------------------------------
-- Frequency data {ch, freq}
----------------------------------------------------------------
local channelsData = {
  A = { {1,5865},{2,5845},{3,5825},{4,5805},{5,5785},{6,5765},{7,5745},{8,5725} },
  B = { {1,5733},{2,5752},{3,5771},{4,5790},{5,5809},{6,5828},{7,5847},{8,5866} },
  E = { {1,5705},{2,5685},{3,5665},{4,5645},{5,5885},{6,5905},{7,5925},{8,5945} },
  F = { {1,5740},{2,5760},{3,5780},{4,5800},{5,5820},{6,5840},{7,5860},{8,5880} },
  R = { {1,5658},{2,5695},{3,5732},{4,5769},{5,5806},{6,5843},{7,5880},{8,5917} },
  L = { {1,5362},{2,5399},{3,5436},{4,5473},{5,5510},{6,5547},{7,5584},{8,5621} },
  X = { {1,4990},{2,5020},{3,5050},{4,5080},{5,5110},{6,5140},{7,5170},{8,5200} }
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function add(t,v) t[#t+1]=v end
local function removeAt(t,i) for k=i,#t-1 do t[k]=t[k+1] end t[#t]=nil end
local function populateRanges() local r={"A","B","E","F","R","L"} if includeXBand then r[#r+1]="X" end return r end
local function calcDistance(a,b) local d=a[3]-b[3]; return d<0 and -d or d end
local function findBestNext(all,current)
  local best,maxMin=nil,-1
  for i=1,#all do local c=all[i]; local minD=99999
    for j=1,#current do local d=calcDistance(c,current[j]); if d<minD then minD=d end end
    if minD>maxMin then best,maxMin=c,minD end
  end
  return best
end

local function calculate()
  local act=populateRanges(); local all={}
  for i=1,#act do local r=act[i]; for j=1,#channelsData[r] do add(all,{r,channelsData[r][j][1],channelsData[r][j][2]}) end end
  for i=#all,1,-1 do local a=all[i]; for j=1,#userSelected do local u=userSelected[j]; if a[1]==u[1] and a[2]==u[2] then removeAt(all,i) break end end end
  calculated={}; for i=1,#userSelected do calculated[i]=userSelected[i] end
  local maxPilots=math.min(6,math.max(pilots,#userSelected))
  while #calculated<maxPilots do local nxt=findBestNext(all,calculated); if not nxt then break end add(calculated,nxt); for k=1,#all do if all[k]==nxt then removeAt(all,k) break end end end
end

----------------------------------------------------------------
-- Visualization (for color radios)
----------------------------------------------------------------
local function drawVisualization(list)
  if not COLOR or #list==0 then return end
  local cx,cy=LCD_W//2,(LCD_H//2)+45
  local radius,vertexCount=85,5
  local angleStep=(2*math.pi)/vertexCount
  local verts={}
  for i=1,vertexCount do local a=-math.pi/2+(i-1)*angleStep; verts[i]={x=cx+math.cos(a)*radius,y=cy+math.sin(a)*radius,data=list[i+1]} end
  if list[1] then lcd.setColor(CUSTOM_COLOR,lcd.RGB(0,200,100)); lcd.drawFilledCircle(cx,cy,9,CUSTOM_COLOR); lcd.drawText(cx-10,cy-26,string.format("%s%d",list[1][1],list[1][2]),SMLSIZE+INVERS) end
  for i=1,vertexCount do
    local v1,v2=verts[i],verts[(i%vertexCount)+1]; local c1,c2=v1.data,v2.data
    local col=(c1 and c2) and lcd.RGB(255,180,0) or lcd.RGB(80,80,80)
    lcd.setColor(CUSTOM_COLOR,col); lcd.drawLine(v1.x,v1.y,v2.x,v2.y,SOLID,CUSTOM_COLOR)
    if c1 and c2 then local mx,my=(v1.x+v2.x)/2,(v1.y+v2.y)/2; local df=math.abs(c1[3]-c2[3]); lcd.drawText(mx-16,my-5,string.format("%d MHz",df),SMLSIZE) end
  end
  for i=1,vertexCount do local v=verts[i]; local c=v.data; local col=c and lcd.RGB(255,150,0) or lcd.RGB(100,100,100); lcd.setColor(CUSTOM_COLOR,col); lcd.drawLine(cx,cy,v.x,v.y,SOLID,CUSTOM_COLOR)
    if c and list[1] then local df=math.abs(c[3]-list[1][3]); lcd.drawText((cx+v.x)/2-16,(cy+v.y)/2-5,string.format("%d MHz",df),SMLSIZE) end end
  for i=1,vertexCount do local v=verts[i]; if v.data then lcd.setColor(CUSTOM_COLOR,lcd.RGB(0,120,255)); lcd.drawFilledCircle(v.x,v.y,7,CUSTOM_COLOR); lcd.drawText(v.x-8,v.y-18,string.format("%s%d",v.data[1],v.data[2]),SMLSIZE)
    else lcd.setColor(CUSTOM_COLOR,lcd.RGB(100,100,100)); lcd.drawFilledCircle(v.x,v.y,6,CUSTOM_COLOR) end end
end

----------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------
local page, selRangeIdx, selChanIdx, editIndex = 1, 1, 1, 1
local infoPage=false
local maxIndex=6  -- 1..4 fields, 5=Calc, 6=Info

local function drawChannels(list,y0)
  local colW=LCD_W//2; local x1,x2=5,colW+5; local rowH=COLOR and 14 or 10
  for i=1,#list do local c=list[i]; local col=(i-1)%2; local row=(i-1)//2; local x=(col==0) and x1 or x2; local y=y0+row*rowH
    lcd.drawText(x,y,string.format("%s%d",c[1],c[2])); lcd.drawText(x+40,y,string.format("%d",c[3])) end
end

local function drawInfoPage()
  lcd.clear()
  lcd.drawFilledRectangle(0,0,LCD_W,40,SOLID)
  lcd.drawText((LCD_W-140)//2,8,"Information",MIDSIZE+INVERS)
  local y=60
  lcd.drawText(10,y,"Utility that helps split",MIDSIZE)
  lcd.drawText(10,y+26,"video channels between",MIDSIZE)
  lcd.drawText(10,y+52,"pilots flying together.",MIDSIZE)
  lcd.drawText(10,y+84,"Finds most distant",MIDSIZE)
  lcd.drawText(10,y+110,"channels by frequency.",MIDSIZE)
  lcd.drawText(10,y+142,"Based on vtx.in.ua/ch/",MIDSIZE)
  lcd.drawText(40,LCD_H-26,"[ENTER]/[BACK] to close",SMLSIZE)
end

----------------------------------------------------------------
-- DRAW
----------------------------------------------------------------
local function draw()
  lcd.clear()
  local headerH=40
  lcd.drawFilledRectangle(0,0,LCD_W,headerH,SOLID)
  lcd.drawText((LCD_W-310)//2,5," Channel Distribution Calculator ",MIDSIZE+INVERS)

  local x1,x2=10,LCD_W//2+10
  local y=headerH+12
  local lh,gap=COLOR and 22 or 14,8

  if page==1 then
    local f=COLOR and MIDSIZE or 0
    lcd.drawText(x1,y,CHAR_INPUT.." Band:",f+(editIndex==1 and INVERS or 0))
    lcd.drawText(x1+110,y,ranges[selRangeIdx],f+(editIndex==1 and INVERS or 0))
    lcd.drawText(x2,y,CHAR_INPUT.." Channel:",f+(editIndex==2 and INVERS or 0))
    lcd.drawText(x2+130,y,tostring(selChanIdx),f+(editIndex==2 and INVERS or 0))
    y=y+lh+gap
    lcd.drawText(x1,y,CHAR_TRAINER.." Pilots:",f+(editIndex==3 and INVERS or 0))
    lcd.drawText(x1+110,y,tostring(pilots),f+(editIndex==3 and INVERS or 0))
    lcd.drawText(x2,y,CHAR_CHANNEL.." Include X:",f+(editIndex==4 and INVERS or 0))
    lcd.drawText(x2+150,y,includeXBand and "Yes" or "No",f+(editIndex==4 and INVERS or 0))
    y=y+lh+18
    lcd.drawText((LCD_W-240)//2,y,"  [CALCULATE]  ",DBLSIZE+(editIndex==5 and INVERS or 0))
    drawChannels(userSelected,y+40)

    lcd.drawText(10,LCD_H-40,"[PAGE>] / [PAGE<] - select, [SCROLL] - change",SMLSIZE)
    lcd.drawText(10,LCD_H-20,"[ENTER] - add/remove, [RTN] - exit/back",SMLSIZE)
    lcd.drawText(LCD_W-100,LCD_H-40,CHAR_LUA.." Info",MIDSIZE+(editIndex==6 and INVERS or 0))

  else
    if COLOR then drawChannels(calculated,headerH+10); drawVisualization(calculated)
    else drawChannels(calculated,headerH+10) end
  end
end

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------
local function run(event)
  if infoPage then
    if event==EVT_ENTER_BREAK or event==EVT_EXIT_BREAK or event==EVT_RTN_BREAK then infoPage=false; page=1; draw(); return 0
    else drawInfoPage(); return 0 end
  end

  if event==EVT_EXIT_BREAK then if page==2 then page=1 else return 2 end
  elseif event==EVT_VIRTUAL_NEXT_PAGE then editIndex=math.min(editIndex+1,maxIndex)
  elseif event==EVT_VIRTUAL_PREV_PAGE then editIndex=math.max(editIndex-1,1)
  elseif event==EVT_ROT_RIGHT then
    if editIndex==1 and selRangeIdx<#ranges then selRangeIdx=selRangeIdx+1
    elseif editIndex==2 and selChanIdx<#channelsData[ranges[selRangeIdx]] then selChanIdx=selChanIdx+1
    elseif editIndex==3 and pilots<6 then pilots=pilots+1
    elseif editIndex==4 then includeXBand=true end
  elseif event==EVT_ROT_LEFT then
    if editIndex==1 and selRangeIdx>1 then selRangeIdx=selRangeIdx-1
    elseif editIndex==2 and selChanIdx>1 then selChanIdx=selChanIdx-1
    elseif editIndex==3 and pilots>2 then pilots=pilots-1
    elseif editIndex==4 then includeXBand=false end
  elseif event==EVT_ENTER_BREAK then
    if page==1 then
      if editIndex==5 then
        calculate(); page=2
      elseif editIndex==6 then
        infoPage=true
      elseif editIndex==2 or editIndex==1 then  -- Only add/remove when Band/Channel is active
        local r=ranges[selRangeIdx]; local ch=channelsData[r][selChanIdx]
        local found; for i=1,#userSelected do local u=userSelected[i]; if u[1]==r and u[2]==ch[1] then found=i break end end
        if found then removeAt(userSelected,found)
        else if #userSelected>=5 then popupMsg,popupTimer="Max 5 channels!",getTime()+200
          else add(userSelected,{r,ch[1],ch[2]}); pilots=math.min(6,#userSelected+1) end end
      end
    end
  elseif event==EVT_RTN_BREAK then if page==2 then page=1 end end
  draw(); return 0
end

return { run=run }
