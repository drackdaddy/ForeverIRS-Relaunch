local _, I = ...
I.ASSESSMENT_NOTE = "These counters describe what the game reported. New characters, bank alts and specialists can have different records; missing counters and resets can affect them. The activity summary does not grade characters."
I.professionKeys = {"firstAid","cooking","fishing","alchemy","blacksmithing","enchanting","leatherworking","mining","herbalism","skinning","tailoring","engineering"}
I.activityKeys = {"questCount","kills","dungeons","disenchanted","disenchantMaterials","fishCaught","honorableKills","flights","deaths"}

function I.professions(snapshot)
    local rows={}
    for _,key in ipairs(I.professionKeys) do
        rows[#rows+1]={key=key,label=I.byKey[key][3],highest=I.byKey[key][5]==true,n=I.numeric(snapshot,key)}
    end
    table.sort(rows,function(a,b)
        if a.n==nil and b.n~=nil then return false end
        if b.n==nil and a.n~=nil then return true end
        if a.n~=b.n then return a.n>b.n end
        return a.label<b.label
    end)
    return rows
end

-- Summarize returned counters without grading a character or inferring play style.
function I.assess(snapshot)
    local known,total,positive=0,0,0
    local evidence={}
    for _,key in ipairs({"questCount","kills","dungeons","honorableKills","disenchanted","disenchantMaterials","fishCaught"}) do
        local n=I.numeric(snapshot,key)
        total=total+1
        if n~=nil then known=known+1;if n>0 then positive=positive+1 end end
        evidence[#evidence+1]=I.byKey[key][3]..": "..I.value(snapshot,key,true)
    end
    local rankKnown,rankPositive=0,0
    for _,key in ipairs(I.professionKeys) do
        local rank=I.numeric(snapshot,key)
        total=total+1
        if rank~=nil then known=known+1;rankKnown=rankKnown+1 end
        if rank and rank>0 then positive=positive+1;rankPositive=rankPositive+1 end
    end
    evidence[#evidence+1]="Professions: "..rankPositive.." with recorded ranks above zero; "..rankKnown.." / "..#I.professionKeys.." readable. Historical ranks can include unlearned professions."
    evidence[#evidence+1]="Auctions: "..I.value(snapshot,"posted",true).." posted; "..I.value(snapshot,"purchases",true).." purchases."
    return {key=known>0 and "recorded" or "unknown",title=known>0 and "Recorded activity" or "Activity counters unavailable",
        summary=known>0 and (positive.." of the "..known.." readable activity counters have values above zero. Missing values are not zero.")
            or "This capture has no readable activity counters. Missing values are not zero.",
        tone=known>0 and "neutral" or "muted",known=known,total=total,positive=positive,evidence=evidence,
        coverage=known.." / "..total.." activity counters readable · missing is not zero"}
end

-- Risk factor: the share of a character's peak gold above its total gold acquired,
-- placed on a four-step scale. It gives players data to weigh and accuses no one.
-- Computed from a capture on demand, so it sends no requests, uses no events, and
-- stores nothing in ForeverIRSDB.
I.RATING_MIN_GOLD = 50000 -- 5g of peak gold, in copper.
-- Each level's name and the lowest outside-gold percentage that reaches it.
I.RISK_LEVELS = {{"Low",0},{"Moderate",25},{"Elevated",50},{"High",75}}
I.RISK_SCALE = "Scale: Low under 25%, Moderate 25-49%, Elevated 50-74%, High 75% or more of peak gold."
I.RATING_METHOD = "Outside gold is peak gold above total gold acquired. A test trade did not raise acquired gold, so gold above that total came from outside the game's recorded income. Gold spent before it raised peak gold does not show, so this is a low estimate and a Low reading does not clear anyone."
I.RATING_NOTE = "A risk factor is not an accusation or the chance that gold was bought. IRS cannot see where gold came from: gifts, alts, guild funds and player trades look the same as purchased gold."
I.RATING_LINE = I.INCOME_DISCLAIMER.." Gifts, alts, guild funds and player trades look the same."
I.RATING_MISSING = "Not rated: peak and acquired gold are both needed."
I.UNITEMIZED_NOTE = "Total gold acquired minus the four income rows, never below zero. The game recorded this gold without a category. It does not affect the risk factor."
-- Peak above acquired is the floor for outside gold: on build 1.60.1.70790 a test
-- trade did not raise acquired gold, so the game's own income total cannot explain
-- it. Mail is untested. snapshot: a capture, or nil. Returns {percent,level,risk,
-- outside,peak,acquired} when rated, otherwise {reason}. A missing counter is
-- never treated as zero: that would inflate the percentage.
function I.rating(snapshot)
    local peak,acquired=I.numeric(snapshot,"peak"),I.numeric(snapshot,"acquired")
    if peak==nil or acquired==nil then return {reason=I.RATING_MISSING} end
    if peak<I.RATING_MIN_GOLD then
        return {reason="Not rated: under "..I.quantity(I.RATING_MIN_GOLD/10000).."g peak gold."}
    end
    local outside=math.max(0,peak-acquired)
    -- Multiply first: 0.29*100 falls just short of 29 and would land one percent low.
    local percent=math.floor(outside*100/peak)
    local level=1
    for n,def in ipairs(I.RISK_LEVELS) do if percent>=def[2] then level=n end end
    return {percent=percent,level=level,risk=I.RISK_LEVELS[level][1],outside=outside,peak=peak,acquired=acquired}
end
-- Gold the game recorded as acquired but the four income rows do not itemize.
-- snapshot: a capture, or nil. Returns copper, or nil when a counter is missing.
function I.unitemized(snapshot)
    local remaining=I.numeric(snapshot,"acquired")
    if remaining==nil then return nil end
    for _,key in ipairs({"looted","quests","vendors","auctions"}) do
        local n=I.numeric(snapshot,key)
        if n==nil then return nil end
        remaining=remaining-n
    end
    return math.max(0,remaining)
end
