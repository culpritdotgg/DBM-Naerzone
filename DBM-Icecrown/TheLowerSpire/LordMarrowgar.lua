local mod	= DBM:NewMod("LordMarrowgar", "DBM-Icecrown", 1)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20220918161536")
mod:SetCreatureID(36612)
mod:SetUsedIcons(1, 2, 3, 4, 5, 6, 7, 8)

mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 69076",
	"SPELL_AURA_REMOVED 69065 69076",
	"SPELL_CAST_START 69057 70826 72088 72089 73144 73145 69076",
	"SPELL_PERIODIC_DAMAGE",
	"SPELL_PERIODIC_MISSED",
	"SPELL_SUMMON 69062 72669 72670"
)

local myRealm = select(3, DBM:GetMyPlayerInfo())

local preWarnWhirlwind		= mod:NewSoonAnnounce(69076, 3)
local warnBoneSpike			= mod:NewCastAnnounce(69057, 2)
local warnImpale			= mod:NewTargetNoFilterAnnounce(72669, 3)

local specWarnColdflame		= mod:NewSpecialWarningGTFO(69146, nil, nil, nil, 1, 8)
local specWarnWhirlwind		= mod:NewSpecialWarningRun(69076, nil, nil, nil, 4, 2)

local timerBoneSpike		= mod:NewCDTimer(15, 69057, nil, nil, nil, 1, nil, DBM_COMMON_L.DAMAGE_ICON, true) -- Has two sets of spellIDs, one before bone storm and one during bone storm (both sets are separated below). Will use UNIT_SPELLCAST_START for calculations since it uses spellName and thus already groups them in the log. 5s variance [15-20]. Added "keep" arg (10N Icecrown 2022/08/25 || 25H Lordaeron 2022/09/14) - pull:15.0, 19.0, 15.2, 49.5 || pull:15.0, 17.3, 16.5, 18.7, 16.0, 19.6, 18.9, 18.7, 16.4, 19.3, 16.0
local timerWhirlwindCD		= mod:NewCDTimer(30, 69076, nil, nil, nil, 2, nil, DBM_COMMON_L.MYTHIC_ICON, true) -- 5s variance? Added "keep" arg
local timerWhirlwind		= mod:NewBuffActiveTimer(20, 69076, nil, nil, nil, 6)
local timerBoned			= mod:NewAchievementTimer(8, 4610)
local timerBoneSpikeUp		= mod:NewCastTimer(69057)
local timerWhirlwindStart	= mod:NewCastTimer(69076)

local soundBoneSpike		= mod:NewSound(69057)
local soundBoneStorm		= mod:NewSound(69076)

local berserkTimer			= mod:NewBerserkTimer((myRealm == "Lordaeron" or myRealm == "Frostmourne") and 360 or 600)

mod:AddSetIconOption("SetIconOnImpale", 72669, true, 0, {8, 7, 6, 5, 4, 3, 2, 1})

mod.vb.impaleIcon = 8

function mod:OnCombatStart(delay)
	preWarnWhirlwind:Schedule(40-delay)
	timerWhirlwindCD:Start(45-delay) -- REVIEW! variance? (10N Icecrown 2022/08/25 || 25H Lordaeron 2022/09/08 || 25H Lordaeron 2022/09/14) - pull:52.2 || pull:48.3 || pull:45.2
	timerBoneSpike:Start(15-delay) -- Fixed timer - 15.0
	berserkTimer:Start(-delay)
end

function mod:OnCombatEnd()
	DBM.BossHealth:Clear()
end
function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == 69076 then						-- Bone Storm (Whirlwind)
		specWarnWhirlwind:Show()
		specWarnWhirlwind:Play("justrun")
		if self:IsHeroic() then
			timerWhirlwind:Show(37)			--36-38 on HC
		else
			timerWhirlwind:Show()			--30 on Norm (10N Icecrown 2022/08/25) - pull:52.2
			timerBoneSpike:Cancel()						-- He doesn't do Bone Spike Graveyard during Bone Storm on normal
		end
	end
end

function mod:SPELL_AURA_REMOVED(args)
	local spellId = args.spellId
	if spellId == 69065 then						-- Impaled
		if self.Options.SetIconOnImpale then
			self:SetIcon(args.destName, 0)
		end
	elseif spellId == 69076 then
		timerWhirlwind:Cancel()
		timerWhirlwindCD:Start() -- REVIEW! On Jul 3, 2021 I changed this to only trigger on Bone Storm finish, although looking at TC script this might be sllightly innacurate since it reschedules on EVENT_WARN_BONE_STORM... Keep a close eye on this with more log data and also VOD review (25H Lordaeron 2022/09/14) - [-36s cf] 33.4, 32.7
		preWarnWhirlwind:Schedule(25)
		if self:IsNormal() then
			timerBoneSpike:Start(15)					-- He will do Bone Spike Graveyard 15 seconds after whirlwind ends on normal
		end
	end
end

function mod:SPELL_CAST_START(args)
	if args:IsSpellID(69057, 70826, 72088, 72089) or args:IsSpellID(73144, 73145) then	-- Bone Spike Graveyard (no bone storm) | (during bone storm HC). REVIEW!
		warnBoneSpike:Show()
		timerBoneSpike:Start()
		timerBoneSpikeUp:Start()
		soundBoneSpike:Play("Interface\\AddOns\\DBM-Core\\sounds\\RaidAbilities\\Bone_Spike_cast.mp3")
	elseif args.spellId == 69076 then
		timerWhirlwindCD:Cancel()
		timerWhirlwindStart:Start()
		soundBoneStorm:Play("Interface\\AddOns\\DBM-Core\\sounds\\RaidAbilities\\Bone_Storm_cast.mp3")
	end
end

function mod:SPELL_PERIODIC_DAMAGE(_, _, _, destGUID, _, _, spellId, spellName)
	if (spellId == 69146 or spellId == 70823 or spellId == 70824 or spellId == 70825) and destGUID == UnitGUID("player") and self:AntiSpam() then		-- Coldflame, MOVE!
		specWarnColdflame:Show(spellName)
		specWarnColdflame:Play("watchfeet")
	end
end
mod.SPELL_PERIODIC_MISSED = mod.SPELL_PERIODIC_DAMAGE

function mod:SPELL_SUMMON(args)
	if args:IsSpellID(69062, 72669, 72670) then			-- Impale
		warnImpale:CombinedShow(0.3, args.sourceName)
		timerBoned:Restart()
		if self.Options.SetIconOnImpale then
			self:SetIcon(args.sourceName, self.vb.impaleIcon)
		end
		if self.vb.impaleIcon < 1 then
			self.vb.impaleIcon = 8
		end
		self.vb.impaleIcon = self.vb.impaleIcon - 1
	end
end