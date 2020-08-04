ScriptName dubhMonitorEffectScript Extends ActiveMagicEffect

Import dubhUtilityScript

; =============================================================================
; PROPERTIES
; =============================================================================

GlobalVariable Property Global_fBestSkillContribMax Auto
GlobalVariable Property Global_fLOSDistanceMax Auto
GlobalVariable Property Global_fFOVPenaltyClear Auto
GlobalVariable Property Global_fFOVPenaltyDistorted Auto
GlobalVariable Property Global_fFOVPenaltyPeripheral Auto
GlobalVariable Property Global_fLOSPenaltyFar Auto
GlobalVariable Property Global_fLOSPenaltyMid Auto
GlobalVariable Property Global_fMobilityBonus Auto
GlobalVariable Property Global_fMobilityPenalty Auto
GlobalVariable Property Global_fScriptDistanceMax Auto
GlobalVariable Property Global_fScriptSuspendTime Auto
GlobalVariable Property Global_fScriptSuspendTimeBeforeAttack Auto
GlobalVariable Property Global_fScriptUpdateFrequencyMonitor Auto
GlobalVariable Property Global_iCrimeArrestOnSightNonViolentThreshold Auto
GlobalVariable Property Global_iPapyrusLoggingEnabled Auto

Actor Property PlayerRef Auto
Faction Property PlayerFaction Auto
FormList Property BaseFactions Auto
FormList Property DisguiseFactions Auto
FormList Property DisguiseFormLists Auto
FormList Property ExcludedDamageSources Auto
FormList Property GuardFactions Auto
MagicEffect Property FactionEnemyEffect Auto
Message Property DisguiseWarningSuspicious Auto   ; "You are being watched..." (5 second delay)
Spell Property FactionEnemyAbility Auto
Spell Property MonitorAbility Auto

; Sequences
GlobalVariable[] Property rgRaceWeights Auto
GlobalVariable[] Property rgSlotWeights Auto
Race[] Property rgRaces Auto

; =============================================================================
; SCRIPT-LOCAL VARIABLES
; =============================================================================

Actor NPC
Bool[] FactionStatesPlayer
Bool[] FactionStatesTarget

; ===============================================================================
; FUNCTIONS
; ===============================================================================

Function _Log(String asTextToPrint, Int aiSeverity = 0)
  If Global_iPapyrusLoggingEnabled.GetValue() as Bool
    Debug.OpenUserLog("MasterOfDisguise")
    Debug.TraceUser("MasterOfDisguise", "dubhMonitorEffectScript> " + asTextToPrint, aiSeverity)
  EndIf
EndFunction


Function LogInfo(String asTextToPrint)
  _Log("[INFO] " + asTextToPrint, 0)
EndFunction


Function LogWarning(String asTextToPrint)
  _Log("[WARN] " + asTextToPrint, 1)
EndFunction


Function LogError(String asTextToPrint)
  _Log("[ERRO] " + asTextToPrint, 2)
EndFunction


Float Function CalculateBestSkillWeight()
  ; Calculates the skill score for the player's best skill

  Float fBestSkillValue = GetBestSkill(PlayerRef)

  Return ((Global_fBestSkillContribMax.GetValue() * Mathf.Min(fBestSkillValue, 100.0)) / 100.0)
EndFunction


Bool[] Function WhichSlotsEquipped(Int aiFactionIndex)
  Bool[] rgSlotsEquipped = new Bool[10]

  Form[] rgWornEquipment = TurtleClub.GetWornEquipment(PlayerRef)

  If !rgWornEquipment
    LogError("rgWornEquipment was None - cannot get worn equipment for Player")
    Return rgSlotsEquipped
  EndIf

  If rgWornEquipment.Length == 0
    LogWarning("rgWornEquipment was empty - Player has no worn equipment")
    Return rgSlotsEquipped
  EndIf

  FormList kCurrentDisguise = DisguiseFormLists.GetAt(aiFactionIndex) as FormList

  ; WARN: if length of DisguiseFormLists increases, this will blow up
  rgSlotsEquipped = TurtleClub.SearchListForForms(kCurrentDisguise, rgWornEquipment)

  Return rgSlotsEquipped
EndFunction


Float Function CalculateEquipWeight(Bool[] rgEquippedSlots)
  ; Returns the equipment score from worn items
  ; 1. Get worn items
  ; 2. Check if worn items are in formlist
  ; 3. If worn items are in formlist, return those slots as Bool array

  Float fEquipScore = 0.0

  ; Hair and Circlet
  If rgEquippedSlots[0] || rgEquippedSlots[7]
    ; Both
    If rgEquippedSlots[0] && rgEquippedSlots[7]
      fEquipScore += (rgSlotWeights[7] as GlobalVariable).GetValue()
    Else
      ; Hair, but not Circlet
      If rgEquippedSlots[0] && !rgEquippedSlots[7]
        fEquipScore += (rgSlotWeights[0] as GlobalVariable).GetValue()
      ; Circlet, but not Hair
      Else
        fEquipScore += (rgSlotWeights[7] as GlobalVariable).GetValue()
      EndIf
    EndIf
  EndIf

  Int i = 1
  While i < 7
    If rgEquippedSlots[i]
      fEquipScore += (rgSlotWeights[i] as GlobalVariable).GetValue()
    EndIf
    i += 1
  EndWhile

  ; Weapons Left and Right
  If rgEquippedSlots[8] || rgEquippedSlots[9]
    If rgEquippedSlots[8]
      fEquipScore += (rgSlotWeights[8] as GlobalVariable).GetValue()
    ElseIf rgEquippedSlots[9]
      fEquipScore += (rgSlotWeights[9] as GlobalVariable).GetValue()
    EndIf
  EndIf

  Return Mathf.Clamp(fEquipScore, 0, 100)
EndFunction


Float Function LookupRaceWeight(Int aiFactionIndex)
  ; Calculates the race score for player based on faction

  Race kPlayerRace = PlayerRef.GetRace()

  Int iRaceIndex = TurtleClub.LookupRaceWeightIndex(aiFactionIndex, kPlayerRace, rgRaces)

  If iRaceIndex < 0
    LogWarning("Cannot find player race in race weight table: aiFactionIndex = " + aiFactionIndex + ", kPlayerRace = " + kPlayerRace)
    Return 0.0
  EndIf

  Float fRaceWeight = (rgRaceWeights[iRaceIndex] as GlobalVariable).GetValue()

  If Mathf.InRange(aiFactionIndex, 0, 2) || Mathf.InRange(aiFactionIndex, 5, 7) || Mathf.InRange(aiFactionIndex, 13, 19) || Mathf.InRange(aiFactionIndex, 21, 23)
    Return fRaceWeight
  EndIf

  If aiFactionIndex == 11 || aiFactionIndex == 25 || aiFactionIndex == 27
    Return fRaceWeight
  EndIf

  If aiFactionIndex == 3 || aiFactionIndex == 12 || aiFactionIndex == 28
    Return -fRaceWeight
  EndIf

  If aiFactionIndex == 4
    Return Mathf.IfThen(iRaceIndex == 2, fRaceWeight, -fRaceWeight)
  EndIf

  If aiFactionIndex == 8 || aiFactionIndex == 9 || aiFactionIndex == 20 || aiFactionIndex == 26
    Return Mathf.IfThen(iRaceIndex == 12, fRaceWeight, -fRaceWeight)
  EndIf

  If aiFactionIndex == 10
    Return Mathf.IfThen(iRaceIndex == 6 || iRaceIndex == 18, fRaceWeight, -fRaceWeight)
  EndIf

  If aiFactionIndex == 24
    Return Mathf.IfThen(iRaceIndex == 12 || iRaceIndex == 14, fRaceWeight, -fRaceWeight)
  EndIf

  If aiFactionIndex == 29
    Return Mathf.IfThen(iRaceIndex == 16, fRaceWeight, -fRaceWeight)
  EndIf

  If aiFactionIndex == 30
    Return Mathf.IfThen(iRaceIndex == 6, -fRaceWeight, fRaceWeight)
  EndIf

  Return 0.0
EndFunction


Float Function Roll(Int aiFactionIndex)
  ; Returns a value between 0.0 and 1.0 weighted by skill, race, and equipment

  Float result = 0.0
  result += CalculateBestSkillWeight()
  result += LookupRaceWeight(aiFactionIndex)

  Bool[] rgSlotsEquipped = WhichSlotsEquipped(aiFactionIndex)
  result += CalculateEquipWeight(rgSlotsEquipped)

  Return Mathf.Min(Mathf.Clamp(result, 0, 100) * 0.01, 1)
EndFunction


Int Function FindActiveDisguise()
  ; Returns the index of the active disguise faction when player and NPC are in matching factions

  If !TurtleClub.ActorIsInAnyFaction(PlayerRef, DisguiseFactions)
    Return -1
  EndIf

  If NPC && !TurtleClub.ActorIsInAnyFaction(NPC, BaseFactions)
    Return -1
  EndIF

  Int i = 0

  While i < FactionStatesPlayer.Length && NPC
    If FactionStatesPlayer[i] && FactionStatesTarget[i]
      If NPC && TurtleClub.ActorIsInFaction(NPC, BaseFactions.GetAt(i) as Faction)
        Return i
      EndIf
    EndIf

    i += 1
  EndWhile

  Return -1
EndFunction


Float Function QueryFOVPenalty(Int aiFovType)
  ; Returns the FOV penalty to max FOV width (affects NPC roll)

  If aiFovType == 1 ; Clear
    Return Global_fFOVPenaltyClear.GetValue()
  EndIf

  If aiFovType == 2 ; Distorted
    Return Global_fFOVPenaltyDistorted.GetValue()
  EndIf

  If aiFovType == 3 ; Peripheral
    Return Global_fFOVPenaltyPeripheral.GetValue()
  EndIf

  Return 1.0
EndFunction


Float Function QueryLOSPenalty(Int aiLosType)
  ; Returns the LOS penalty to max LOS distance (affects NPC roll)

  If aiLosType == 1 ; Near
    Return 1.0
  EndIf

  If aiLosType == 2 ; Mid
    Return Global_fLOSPenaltyMid.GetValue()
  EndIf

  If aiLosType == 3 ; Far
    Return Global_fLOSPenaltyFar.GetValue()
  EndIf

  Return 1.0
EndFunction


Float Function QueryMobilityMult()
  ; Retrieves mobility bonus or penalty (affects Player roll)

  If PlayerRef.IsRunning() || PlayerRef.IsSprinting() || PlayerRef.IsSneaking() || PlayerRef.IsWeaponDrawn()
    Return Global_fMobilityPenalty.GetValue()
  EndIf

  Return Global_fMobilityBonus.GetValue()
EndFunction


Bool Function TryToDiscoverPlayer(Int aiFactionIndex)
  ; Returns whether PlayerRef was discovered by NPC

  If !NPC
    Return False
  EndIf

  If NPC && !NPC.HasLOS(PlayerRef)
    LogInfo("Cannot start rolling for discovery because " + NPC + " lost line of sight to Player")
    Return False
  EndIf

  Float fLightLevel = PlayerRef.GetLightLevel()

  Float fMaxDistance = (Global_fLOSDistanceMax.GetValue() * (fLightLevel / 100))

  If Global_fScriptSuspendTime.GetValue() > 0.0
    Float fDistanceToPlayer = NPC.GetDistance(PlayerRef)

    If Mathf.InRange(fDistanceToPlayer, 0.0, fMaxDistance)
      If !PlayerRef.IsRunning() && !PlayerRef.IsSprinting() && !PlayerRef.IsSneaking() && !PlayerRef.IsWeaponDrawn()
        LogInfo("Player is being watched by " + NPC)
        NPC.SetLookAt(PlayerRef)

        DisguiseWarningSuspicious.Show()
        Suspend(Global_fScriptSuspendTime.GetValue())

        If NPC && !NPC.HasLOS(PlayerRef)
          LogInfo("Exiting early while rolling for discovery because " + NPC + " lost line of sight to Player")
          Return False
        EndIf
      EndIf
    EndIf
  EndIf

  Float fMaxHeadingAngle = Game.GetGameSettingFloat("fDetectionViewCone")

  Float fHeadingAngle = NPC.GetHeadingAngle(PlayerRef)

  If !Mathf.InRange(fHeadingAngle, Math.Abs(fMaxHeadingAngle) * -1.0, fMaxHeadingAngle)
    LogInfo("Exiting discovery roll because Player is outside " + NPC + "'s detection view cone")
    Return False
  EndIf

  Float fDistanceToPlayer = NPC.GetDistance(PlayerRef)

  If !Mathf.InRange(fDistanceToPlayer, 0.0, fMaxDistance)
    LogInfo("Exiting discovery roll because light-adjusted distance between " + NPC + " and Player is too great")
    Return False
  EndIf

  If NPC && !NPC.HasLOS(PlayerRef)
    LogInfo("Exiting discovery roll because " + NPC + " lost line of sight to Player")
    Return False
  EndIf

  Int iFovType          = GetFovType(fHeadingAngle, fMaxHeadingAngle)
  Int iLosType          = GetLosType(fDistanceToPlayer, fMaxDistance)

  Float fFOVPenalty     = QueryFOVPenalty(iFovType)
  Float fLOSPenalty     = QueryLOSPenalty(iLosType)

  Float fDiceRollNPC    = Utility.RandomFloat(0.0, 1.0)
  Float fDiceRollPlayer = Roll(aiFactionIndex)

  Float fMobilityMult   = QueryMobilityMult()

  fDiceRollPlayer = fDiceRollPlayer * fMobilityMult
  fDiceRollNPC *= fFOVPenalty
  fDiceRollNPC /= fLOSPenalty

  If fDiceRollPlayer > fDiceRollNPC
    LogInfo("Player won dice roll (" + fDiceRollPlayer + " vs. " + fDiceRollNPC + ") and escaped notice from " + NPC)
    Return False
  EndIf

  LogInfo("Player lost dice roll (" + fDiceRollPlayer + " vs. " + fDiceRollNPC + ") and was discovered by " + NPC)
  Return True
EndFunction


Bool Function TryRemoveMonitorAbility(String asLogMessage)
  If NPC && MonitorAbility && NPC.RemoveSpell(MonitorAbility)
    LogInfo(asLogMessage)
    NPC = None
    Return True
  EndIf
  Return False
EndFunction


Bool Function TryIncreaseBounty(Int aiFactionIndex)
  ; Increases bounty if player is in Thieves Guild Disguise and NPC is in a guard faction

  If aiFactionIndex != 11
    Return False
  EndIf

  If NPC && !TurtleClub.ActorIsInAnyFaction(NPC, GuardFactions)
    Return False
  EndIf

  Faction kCrimeFaction = NPC.GetCrimeFaction()

  If !kCrimeFaction
    Return False
  EndIf

  Int iNonViolentThreshold = Global_iCrimeArrestOnSightNonViolentThreshold.GetValue() as Int

  If kCrimeFaction.GetCrimeGoldNonViolent() < iNonViolentThreshold
    Int result = Mathf.RoundToInt(iNonViolentThreshold * 0.1)
    kCrimeFaction.ModCrimeGold(result, False)
    LogInfo("Increased crime gold by " + result + " for faction: aiFactionIndex = " + aiFactionIndex + ", kCrimeFaction = " + kCrimeFaction)
    Return True
  EndIf

  Return False
EndFunction


; ===============================================================================
; EVENTS
; ===============================================================================

Event OnEffectStart(Actor akTarget, Actor akCaster)
  NPC = akTarget
  If NPC && NPC.Is3DLoaded() && !NPC.IsDead() && NPC.HasSpell(MonitorAbility)
    RegisterForSingleUpdate(Global_fScriptUpdateFrequencyMonitor.GetValue())
  Else
    TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC was not loaded and dead")
  EndIf
EndEvent


Event OnCellDetach()
  TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC's parent cell has been detached")
EndEvent


Event OnDetachedFromCell()
  TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC was detached from the cell")
EndEvent


Event OnUnload()
  TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC has been unloaded")
EndEvent


Event OnUpdate()
  If NPC && !NPC.HasSpell(MonitorAbility)
    LogInfo("Stopping monitor on " + NPC + " because the monitor ability was removed")
    NPC = None
    Return
  EndIf

  If NPC && NPC.IsDead()
    If TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC is dead")
      Return
    EndIf
  EndIf

  ; don't execute anything if the player has a menu open
  If !Utility.IsInMenuMode()
    FactionStatesPlayer = TurtleClub.GetFactionStates(PlayerRef, DisguiseFactions)

    If NPC
      FactionStatesTarget = TurtleClub.GetFactionStates(NPC, BaseFactions)
    Else
      Return
    EndIf

    ; -----------------------------------------------------------------------
    ; ERRANT HOSTILITY
    ; -----------------------------------------------------------------------
    ; no reason to call TryToDiscoverPlayer() if the actor is already hostile
    ; -----------------------------------------------------------------------
    If NPC && !PlayerRef.IsDead() && !NPC.IsDead() && NPC.GetCombatTarget() == PlayerRef && !NPC.HasMagicEffect(FactionEnemyEffect)
      ; player and npc must be in an appropriate disguise/base faction pair
      If FindActiveDisguise() > -1
        ; try to make the npc hostile
        If NPC && NPC.AddSpell(FactionEnemyAbility)
          LogInfo("Attached " + FactionEnemyAbility + " to " + NPC + " due to unknown hostility")
        EndIf
      EndIf
    EndIf

    ; -----------------------------------------------------------------------
    ; CORE LOOP
    ; -----------------------------------------------------------------------
    If NPC && !PlayerRef.IsDead() && !NPC.IsDead()
      ; NPC must satisfy various conditions before running expensive loops and math calculations
      If NPC && !NPC.IsHostileToActor(PlayerRef) && !NPC.HasMagicEffect(FactionEnemyEffect) && !NPC.IsInCombat() && NPC.HasLOS(PlayerRef) && PlayerRef.IsDetectedBy(NPC) && !NPC.IsAlerted() && !NPC.IsArrested() && !NPC.IsArrestingTarget() && !NPC.IsBleedingOut() && !NPC.IsCommandedActor() && !NPC.IsGhost() && !NPC.IsInKillMove() && !NPC.IsPlayerTeammate() && !NPC.IsTrespassing() && !NPC.IsUnconscious() && !Mathf.InRange(NPC.GetSleepState() as Float, 3, 4)
        ; player and NPC must be in an appropriate disguise/base faction pair
        Int iActiveDisguise = FindActiveDisguise()
        If iActiveDisguise > -1
          ; try to roll for detection
          If TryToDiscoverPlayer(iActiveDisguise)
            ; suspend for some amount of seconds, if global set
            Float fTimeBeforeAttack = Global_fScriptSuspendTimeBeforeAttack.GetValue()
            If fTimeBeforeAttack > 0
              Suspend(fTimeBeforeAttack)
            EndIf

            ; ensure that the actor still has line of sight to the Player
            If NPC && NPC.HasLOS(PlayerRef)
              If !TryIncreaseBounty(iActiveDisguise) && NPC.AddSpell(FactionEnemyAbility)
                LogInfo("Attached " + FactionEnemyAbility + " to " + NPC + " who won detection roll")
              EndIf

              NPC.ClearLookAt()
            Else
              If NPC
                LogInfo("Discarded dice roll because " + NPC + " lost line of sight to Player")
                NPC.ClearLookAt()
              EndIf
            EndIf
          Else
            If NPC
              NPC.ClearLookAt()
            EndIf
          EndIf
        EndIf
      EndIf
    EndIf

    ; extra performance management
    Suspend(Global_fScriptUpdateFrequencyMonitor.GetValue())
  EndIf

  If NPC && !NPC.Is3DLoaded()
    If NPC && TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC is not loaded")
      Return
    EndIf
  EndIf

  If NPC && NPC.IsDead()
    If NPC && TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC is dead")
      Return
    EndIf
  EndIf

  If PlayerRef.IsDead()
    If NPC && TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the Player is dead")
      Return
    EndIf
  EndIf

  If NPC && (NPC.GetDistance(PlayerRef) > Global_fScriptDistanceMax.GetValue())
    If NPC && TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the Player is too far away")
      Return
    EndIf
  EndIf

  If NPC
    RegisterForSingleUpdate(Global_fScriptUpdateFrequencyMonitor.GetValue())
  EndIf
EndEvent


Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, Bool abPowerAttack, Bool abSneakAttack, Bool abBashAttack, Bool abHitBlocked)
  If akAggressor != PlayerRef as ObjectReference
    Return
  EndIf

  If PlayerRef.IsDead()
    Return
  EndIf

  If NPC && NPC.IsDead()
    Return
  EndIf

  If NPC && NPC.IsHostileToActor(PlayerRef)
    Return
  EndIf

  If NPC && NPC.HasMagicEffect(FactionEnemyEffect)
    Return
  EndIf

  If ExcludedDamageSources.HasForm(akSource)
    Return
  EndIf

  If !NPC
    Return
  EndIf

  If NPC
    LogInfo(NPC + " was attacked by " + PlayerRef + " with " + akSource)
  EndIf

  If NPC
    ; StartCombat checks if attacker/target are alive, if attacker is in dialogue, and if attacker/target have processes
    ; calls BSTaskPool->QueueStartCombat - how fast NPC starts combat is dependent on task pool
    NPC.StartCombat(PlayerRef)
  EndIf

  If NPC && FactionEnemyAbility && NPC.AddSpell(FactionEnemyAbility)
    LogInfo("Attached " + FactionEnemyAbility + " to " + NPC + " who was hit by " + akAggressor)

    If NPC && TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC was attacked by " + akAggressor)
      Return
    EndIf
  EndIf
EndEvent


Event OnDeath(Actor akKiller)
  If NPC && TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the NPC was killed by " + akKiller)
    Return
  EndIf
EndEvent


Event OnEffectFinish(Actor akTarget, Actor akCaster)
  If NPC && TryRemoveMonitorAbility("Detached monitor from " + NPC + " because the effect finished")
    Return
  EndIf
EndEvent
