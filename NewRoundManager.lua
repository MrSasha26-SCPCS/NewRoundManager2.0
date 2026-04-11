local GameObject = CS.UnityEngine.GameObject
local Time = CS.UnityEngine.Time
local Vector2 = CS.UnityEngine.Vector2
local Vector3 = CS.UnityEngine.Vector3
local SceneManager = CS.UnityEngine.SceneManagement.SceneManager
local Player = CS.Player
local Resources = CS.UnityEngine.Resources

---@class NewRoundManager:CS.Akequ.Base.Room
NewRoundManager = {}

NewRoundManager.NRM_status = "Enable"
NewRoundManager.victory = "None"
NewRoundManager.time = 10
NewRoundManager.time_to_check = 0
NewRoundManager.restart = 0
NewRoundManager.sent = 0
NewRoundManager.round_started = 0
NewRoundManager.escapedScientists = 0
NewRoundManager.escapedClassD = 0
NewRoundManager.printed = false

function NewRoundManager:Init()
    if self.main.netEvent.isServer then        
        self.time = CS.Config.GetInt("restart_time", 10)
        self.time_to_check = CS.Config.GetInt("NRM_time_to_check", 5)
        self.NRM_status = "Enable"
        self.victory = "None"
        self.restart = 0
        self.sent = 0
        self.round_started = 0
        self.escapedScientists = 0
        self.escapedClassD = 0

        local rm = GameObject.FindObjectOfType(typeof(CS.RoundManager))
        GameObject.Destroy(rm)
        rm = nil
        CS.HookManager.Add(self.main.netEvent.gameObject, "changeLockRoundState", function(obj)
            if obj[0] == true then
                self.NRM_status = "Disable"
            else
                self.NRM_status = "Enable"
            end
        end)
        CS.HookManager.Add(self.main.netEvent.gameObject, "onRoundStart", function(obj)
            self.round_started = 1
        end)
        CS.HookManager.Add(self.main.netEvent.gameObject, "RestartRoundAP", function(obj)
            SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex)
        end)
        CS.HookManager.Add(self.main.netEvent.gameObject, "onScientistEscape", function(obj)        
            self.escapedScientists = self.escapedScientists + 1
        end)
        CS.HookManager.Add(self.main.netEvent.gameObject, "onClassDEscape", function(obj)
            self.escapedClassD = self.escapedClassD + 1
        end)
    end
    if self.main.netEvent.isClient then
        local base_ = GameObject.Find("Canvas")
        local victory_text_obj = GameObject("VictoryTextObject")
        victory_text_obj.transform:SetParent(base_.transform, false)
        victory_text_obj.transform.localPosition = Vector3(0, -120, 0)
        local rtv = victory_text_obj:AddComponent(typeof(CS.UnityEngine.RectTransform))
        rtv.anchorMin = Vector2(0.5, 1)
        rtv.anchorMax = Vector2(0.5, 1)
        rtv.pivot = Vector2(0.5, 1)
        rtv.sizeDelta = Vector2(700, 120)
        local victory_text = victory_text_obj:AddComponent(typeof(CS.UnityEngine.UI.Text))
        victory_text.font = Resources.GetBuiltinResource(typeof(CS.UnityEngine.Font), "Arial.ttf")
        victory_text.text = "<size=32><color=white>Раунд окончен!</color></size>"
        victory_text.fontStyle = CS.UnityEngine.FontStyle.Bold
        victory_text.alignment = CS.UnityEngine.TextAnchor.MiddleCenter
        victory_text.enabled = false
        victory_text.raycastTarget = false
    end
end

function NewRoundManager:Update()    
    if self.main.netEvent.isServer and self.round_started == 1 then
        if self.NRM_status == "Enable" then
            if self.restart == 1 then
                if self.sent == 0 then
                    self.main:SendToEveryone("EndRoundClient", self.time, self.victory, self.escapedScientists, self.escapedClassD)
                    self.sent = 1
                end
                self.time = self.time - 1 * Time.deltaTime
                if self.time < 0 then
                    CS.HookManager.Run("RestartRoundAP")
                end
            else
                self.time_to_check = self.time_to_check - 1 * Time.deltaTime
                if self.time_to_check <= 0 then
                    self:Check()
                    self.time_to_check = CS.Config.GetInt("NRM_time_to_check", 3)
                end
            end
        end
    end
end

--SERVER

function NewRoundManager:Check()
    self.restart = 1

    local team_classD = false
    local team_mtf = false
    local team_scp = false
    local team = "None"
    local i = 0
    local players = GameObject.FindObjectsOfType(typeof(Player))

    for i_for = 0, players.Length - 1 do
        local ply  = players[i_for]
        if ply ~= nil then
            if ply.playerClass ~= nil and ply.maxHealth ~= nil then
                if ply.maxHealth < 200 then
                    team = ply.playerClass:GetTeamID()
                elseif ply.playerClass:GetType().Name ~= "SCP999" then
                    team = "SCP"
                else
                    team = "None"
                end
                if team == "ClassD" then
                    if team_classD == false then
                        team_classD = true
                        i = i + 1
                    end
                elseif team == "MTF" then
                    if team_mtf == false then
                        team_mtf = true
                        i = i + 1
                    end
                elseif team == "SCP" then
                    if team_scp == false then
                        team_scp = true
                        i = i + 1
                    end
                end                
            end            
        end       
    end

    if i >= 2 then        
        self.restart = 0
    else
        if team_classD then
            self.victory = "ClassD"
        elseif team_mtf then
            self.victory = "MTF"
        elseif team_scp then
            self.victory = "SCP"
        else
            self.victory = "None"
        end       
        for i_for = 0, players.Length - 1 do
            ply = players[i_for]
            if ply.playerClass ~= nil then
                if ply.playerClass:GetType().Name == "ClassD" then
                    self.escapedClassD = self.escapedClassD + 1
                elseif ply.playerClass:GetType().Name == "Scientist" then
                    self.escapedScientists = self.escapedScientists + 1
                end
            end
        end        
    end
    if self.restart == 1 then
        CS.HookManager.Run("onNRMRoundEnd")
        self.main:SendToEveryone("CLIENTSetVoiceChat")
    end
end

--CLIENT

function NewRoundManager:CLIENTSetVoiceChat()
    CS.PlayerUtilities.SetVoiceChat(CS.PlayerUtilities.CreateValueTuple("Spectator", true))
end

function NewRoundManager:EndRoundClient(got_time, got_victory, scientists, classD)
    self.time = got_time
    self.victory = got_victory
    self.escapedScientists = scientists
    self.escapedClassD = classD
    local text_obj = GameObject.Find("VictoryTextObject")
    local text = text_obj:GetComponent(typeof(CS.UnityEngine.UI.Text))
    text.enabled = true

    if self.victory == "SCP" then
        text.text = "<size=35><color=red>Победа SCP!</color></size>\n<size=20><color=grey>Сбежало <color=yellow>учёных</color>: </color>" .. self.escapedScientists .. "\n<color=grey>Сбежало <color=orange>класса-D</color>: </color>" .. self.escapedClassD .. "\n<color=grey>Перезапуск через <color=white>" .. self.time .. "</color> секунд.</color></size>"
    elseif self.victory == "ClassD" then
        text.text = "<size=35><color=green>Победа Повстанцев Хаоса!</color></size>\n<size=20><color=grey>Cбежало <color=yellow>учёных</color>: </color>" .. self.escapedScientists .. "\n<color=grey>Сбежало <color=orange>класса-D</color>: </color>" .. self.escapedClassD .. "\n<color=grey>Перезапуск через <color=white>" .. self.time .. "</color> секунд.</color></size>"
    elseif self.victory == "MTF" then
        text.text = "<size=35><color=blue>Победа фонда!</color></size>\n<size=20><color=grey>Cбежало <color=yellow>учёных</color>: </color>" .. self.escapedScientists .. "\n<color=grey>Сбежало <color=orange>класса-D</color>: </color>" .. self.escapedClassD .. "\n<color=grey>Перезапуск через <color=white>" .. self.time .. "</color> секунд.</color></size>"
    else
        text.text = "<size=35><color=white>Ничья!</color></size>\n<size=20><color=grey>Cбежало <color=yellow>учёных</color>: </color>" .. self.escapedScientists .. "\n<color=grey>Сбежало <color=orange>класса-D</color>: </color>" .. self.escapedClassD .. "\n<color=grey>Перезапуск через <color=white>" .. self.time .. "</color> секунд.</color></size>"
    end
end

return NewRoundManager