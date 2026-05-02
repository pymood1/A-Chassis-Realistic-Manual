--Apply Power
function Engine(dt)
	local deltaTime = (60/(1/math.max(dt, 0.001)))

	if _LurchTimer > 0 then
		_LurchTimer = math.max(0, _LurchTimer - dt)
	end

	--Neutral Gear
	if ((_CGear == 0 or _Shifting) and _IsOn) then 
		_ClPressing = true
		_Clutch = 1
		_StallOK = false
	end

	local revMin = 0
	local goalMin = _Tune.IdleRPM
	local goalMax = _Tune.Redline

	if _Shifting and _ShiftUp then 
		_GThrot = 0
	elseif _Shifting and _ShiftDn then
		_GThrot = (_Tune.ShiftThrot/100)
	else
		if (_Tune.AutoShiftVers == "Old" and _CGear==-1 and _TMode=="Auto") then
			_GThrot = _InBrake
		else
			_GThrot = _InThrot
		end
	end

	if (_Tune.AutoShiftVers == "Old" and _CGear==-1 and _TMode=="Auto") then
		_GBrake = _InThrot - (_Tune.IdleThrottle/100)
	else
		_GBrake = _InBrake
	end

	if not _IsOn then 
		ticc = tick()
		revMin = 0 
		goalMin = 0
		_GThrot = _Tune.IdleThrottle/100
		if _TMode~="Manual" then 
			_CGear = 0 
			_ClPressing = true 
			_Clutch = 1 
		end
	end

	local governor = 0
	if _RPM < _Tune.IdleRPM and _IsOn and _GThrot <= _Tune.IdleThrottle/100 then
		governor = math.clamp((_Tune.IdleRPM - _RPM) / (_Tune.IdleRPM * 0.8), 0, 0.4)
	end
	local effectiveThrot = math.max(_GThrot + governor, _Tune.IdleThrottle/100)

	if ((_ClPressing and _CGear == 0) or (_PlayerClutch and _CGear ~= 0)) and _Tune.NeutralLimit then
		if (_CGear == 0 and not _Tune.LimitClutch) or _Tune.LimitClutch then
			goalMax = _Tune.NeutralRevRPM
		end
	end

	--Determine RPM
	local maxSpin=0
	local maxCount=0
	local revThrot = effectiveThrot
	for i,v in pairs(Drive) do maxSpin = maxSpin + v.RotVelocity.Magnitude maxCount = maxCount + 1 end
	maxSpin=maxSpin/maxCount

	if _GoalRPM>goalMax+100 then 
		revThrot = _Tune.IdleThrottle/100
	end

	if _Tune.Engine or _Tune.Electric then
		local revDecay = _Tune.RevDecay
		local revAccel = _Tune.RevAccel

		local targetRPM = (_RPM - revDecay * deltaTime) + ((revDecay + revAccel) * revThrot * deltaTime)

		if _ClPressing and targetRPM < _RPM then
			local dropAmount = _RPM - targetRPM
			targetRPM = _RPM - (dropAmount * 0.5)
		end

		local clampMin = _ClPressing and 0 or goalMin
		_GoalRPM = math.clamp(targetRPM, clampMin, _Tune.Redline + 100)
	end

	if _GoalRPM>_Tune.Redline then 
		if _CGear<#_Tune.Ratios-2 then
			_GoalRPM = _GoalRPM-_Tune.RevBounce
		else
			_GoalRPM = _GoalRPM-_Tune.RevBounce*.5
		end
	end

	local _ratio = _Tune.Ratios[_CGear + 2]
	local idleThrot = _Tune.IdleThrottle/100
	local rpmWheelTarget = _spLimit

	local _WheelRPM = maxSpin*_Tune.Ratios[_CGear+2]*fFDr

	--[ 1.4 Realistic Manual: Launch Energy ]
	if _IsOn then
		if _ClPressing and _CGear ~= 0 then
			LaunchBuild = math.min(math.max(LaunchBuild, _RPM), _Tune.Redline)
		elseif LaunchBuild < _Tune.IdleRPM then
			LaunchBuild = math.min(_Tune.IdleRPM, LaunchBuild + (_Tune.RevAccel * 0.25 * deltaTime))
		else
			LaunchBuild = math.max(_Tune.IdleRPM, LaunchBuild - (_Tune.RevDecay * 2 * deltaTime))
		end
	else
		LaunchBuild = math.max(0, LaunchBuild - (_Tune.RevDecay * deltaTime))
	end

	if _Tune.Clutch then
		if script.Parent.Values.AutoClutch.Value and _IsOn then
			if _Tune.ClutchType == "Clutch" then
				if _ClPressing then _ClutchKick = 1 end
				_ClutchKick = _ClutchKick*(_Tune.ClutchEngage/100)		
				local ClRPMInfluence = math.max((_RPM-_Tune.IdleRPM)*_Tune.ClutchRPMMult/(_Tune.Redline-_Tune.IdleRPM),0)
				if _Tune.ClutchMode == "New" then ClRPMInfluence = 0 end
				_ClutchModulate = math.min(((((script.Parent.Values.Velocity.Value.Magnitude/_Tune.SpeedEngage)/math.abs(_CGear)) + ClRPMInfluence) - _ClutchKick), 1)
			elseif _Tune.ClutchType == "CVT" or (_Tune.ClutchType == "TorqueConverter" and _Tune.TQLock) then
				if (_GThrot-(_Tune.IdleThrottle/100)==0 and script.Parent.Values.Velocity.Value.Magnitude<_Tune.SpeedEngage) or (_GThrot-(_Tune.IdleThrottle/100)~=0 and (_RPM < _Tune.RPMEngage and _WheelRPM < _Tune.RPMEngage)) then
					_ClutchModulate = math.min(_ClutchModulate*(_Tune.ClutchEngage/100), 1)
				else
					_ClutchModulate = math.min(_ClutchModulate*(_Tune.ClutchEngage/100)+(1-(_Tune.ClutchEngage/100)), 1)
				end
			elseif _Tune.ClutchType == "TorqueConverter" and not _Tune.TQLock then
				_ClutchModulate = math.min((_RPM/_Tune.Redline)*0.7, 1)
			end
			if not _ClPressing then _Clutch = math.min(1-_ClutchModulate,1) else _Clutch = 1 end
		else
			if _ClPressing then
				_Clutch = math.min(_Clutch + 0.125, 1) 
			else
				_Clutch = math.max(_Clutch - 0.15, 0)
			end
		end
		_StallOK = (_Clutch<=0.01) or _StallOK
	else
		_StallOK = false
		if not _ClPressing and not _Shifting then _Clutch = 0 else _Clutch = 1 end
	end

	-- Physics-based RPM Calculation
	local aRPM = math.max(math.min((_GoalRPM*_Clutch) + (_WheelRPM*(1-_Clutch)),_Tune.Redline+100),revMin)
	local clutchP = math.min(math.abs(aRPM-_RPM)/(_Tune.Flywheel*deltaTime),.9)
	if aRPM < _RPM and not _ClPressing then
		clutchP = math.max(clutchP, 0.3)
	end
	if _ClPressing then clutchP = 0 end
	_RPM = _RPM*clutchP  +  aRPM*(1-clutchP)

	if _IsOn and _StallOK then
		local struggleRPM = _Tune.IdleRPM * 0.45
		if _RPM < struggleRPM then
			local shudderIntensity = 1 - (_RPM / struggleRPM)
			local shudder = (math.random() - 0.5) * 0.4 * shudderIntensity
			_OutTorque = _OutTorque * math.clamp(1 + shudder, 0, 1.5)

			if _RPM <= (_Tune.IdleRPM * 0.3) then
				_StallTimer = _StallTimer + dt
				if _StallTimer > 0.25 + (math.random() * 0.2) then 
					script.Parent.IsOn.Value = not _Tune.Stall
					_StallTimer = 0
				end
			else
				_StallTimer = math.max(0, _StallTimer - dt)
			end
		else
			_StallTimer = 0
		end
	end

	--Rev Limiter
	_spLimit = (_Tune.Redline+100)/(fFDr*_Tune.Ratios[_CGear+2])
	if _RPM>_Tune.Redline then 
		if _CGear<#_Tune.Ratios-2 then
			_RPM = _RPM-_Tune.RevBounce
		else
			_RPM = _RPM-_Tune.RevBounce*.5
		end
	end

	--Aspiration
	local TPsi = _TPsi/math.max(1, _TCount)
	local _BThrot = _GThrot

	if _Tune.Engine then
		if _TCount~=0 and _TCount~=2 then
			_TBoost = _TBoost + ((((((_HP*(_BThrot*1.2)/_Tune.Horsepower)/8)-(((_TBoost/TPsi*(TPsi/15)))))*((8/(_Tune.T_BoostLag/(deltaTime)))*2))/TPsi)*15)
			if _TBoost < 0.05 then _TBoost = 0.05 elseif _TBoost > 2 then _TBoost = 2 end
		elseif _TCount==2 then
			if _TBoost<1 then
				_TBoost = _TBoost + ((((((_HP*(_BThrot*1.2)/_Tune.Horsepower)/8)-(((_TBoost/TPsi*(TPsi/15)))))*((8/(_Tune.T_BoostLag/(deltaTime)))*2))/TPsi)*15)
			elseif _TBoost>=1 then
				_TBoost = _TBoost + ((((((_HP*(_BThrot*1.2)/_Tune.Horsepower)/8)-(((_TBoost/TPsi*(TPsi/15)))))*((8/(_Tune.T2_BoostLag/(deltaTime)))*2))/TPsi)*15)
			end
			if _TBoost < 0.05 then _TBoost = 0.05 elseif _TBoost > 2 then _TBoost = 2 end
		else
			_TBoost = 0
		end
		if _SCount~=0 then
			if _BThrot>sthrot then
				sthrot=math.min(_BThrot,sthrot+_Tune.S_Sensitivity*deltaTime)
			elseif _BThrot<sthrot then
				sthrot=math.max(_BThrot,sthrot-_Tune.S_Sensitivity*deltaTime)
			end
			_SBoost = (_RPM/_Tune.Redline)*(.5+(1.5*sthrot))
		else
			_SBoost = 0
		end
	else
		_TBoost = 0
		_SBoost = 0
	end

	--Torque calculations
	if _Tune.Engine then
		local cTq = NCache[_CGear+2][math.floor(math.min(_Tune.Redline,math.max(0,_RPM))/100)]
		_NH = cTq.Horsepower+(cTq.HpSlope*(((_RPM-math.floor(_RPM/100))/100)%1))
		_NT = cTq.Torque+(cTq.TqSlope*(((_RPM-math.floor(_RPM/100))/100)%1))
		if _TCount~=0 then
			local tTq = TCache[_CGear+2][math.floor(math.min(_Tune.Redline,math.max(0,_RPM))/100)]
			_TH = (tTq.Horsepower+(tTq.HpSlope*(((_RPM-math.floor(_RPM/100))/100)%1)))*(_TBoost/2)
			_TT = (tTq.Torque+(tTq.TqSlope*(((_RPM-math.floor(_RPM/100))/100)%1)))*(_TBoost/2)
		else
			_TH,_TT = 0,0
		end
		if _SCount~=0 then
			local sTq = SCache[_CGear+2][math.floor(math.min(_Tune.Redline,math.max(0,_RPM))/100)]
			_SH = (sTq.Horsepower+(sTq.HpSlope*(((_RPM-math.floor(_RPM/100))/100)%1)))*(_SBoost/2)
			_ST = (sTq.Torque+(sTq.TqSlope*(((_RPM-math.floor(_RPM/100))/100)%1)))*(_SBoost/2)
		else
			_SH,_ST = 0,0
		end
		_BH = _TH+_SH
		_BT = _TT+_ST
	else
		_NH,_NT = 0,0
		_TH,_TT = 0,0
		_SH,_ST = 0,0
		_BH,_BT = 0,0
	end

	if _Tune.Electric and _CGear~=0 then
		local eTq = ECache[_CGear+2][math.floor(math.min(_Tune.Redline,math.max(100,_RPM))/100)]
		_EH = eTq.Horsepower+(eTq.HpSlope*(((_RPM-math.floor(_RPM/100))/100)%1))
		_ET = eTq.Torque+(eTq.TqSlope*(((_RPM-math.floor(_RPM/100))/100)%1))
	else
		_EH,_ET = 0,0
	end

	_HP = _NH + _BH + _EH

	if _HP ~= _HP or _RPM ~= _RPM then
		_HP = 0
		_RPM = _Tune.IdleRPM
		_GoalRPM = _Tune.IdleRPM
		_TBoost = 0.05
		_SBoost = 0
		_TH, _TT = 0, 0
		_SH, _ST = 0, 0
		_BH, _BT = 0, 0
	end

	_OutTorque = _NT + _BT + _ET

	local iComp =(car.DriveSeat.CFrame.lookVector.y)*cGrav
	if _CGear==-1 then iComp=-iComp end

	-- Realistic Manual 1.4: Lurch calculation applied to Torque
	local idleScale = math.clamp(_RPM / math.max(_Tune.IdleRPM, 1), 0, 1)
	_OutTorque = (_NT + _BT + _ET) * idleScale
	_OutTorque = _OutTorque*math.max(1,(1+iComp))

	--Average Rotational Speed Calculation
	local fwspeed=0
	local fwcount=0
	local rwspeed=0
	local rwcount=0

	for i,v in pairs(car.Wheels:GetChildren()) do
		if v.Name=="FL" or v.Name=="FR" or v.Name == "F" then
			fwspeed=fwspeed+v.RotVelocity.Magnitude
			fwcount=fwcount+1
		elseif v.Name=="RL" or v.Name=="RR" or v.Name == "R" then
			rwspeed=rwspeed+v.RotVelocity.Magnitude
			rwcount=rwcount+1
		end
	end
	fwspeed=fwspeed/fwcount
	rwspeed=rwspeed/rwcount	
	local cwspeed=(fwspeed+rwspeed)/2

	--Update Wheels
	for i,v in pairs(car.Wheels:GetChildren()) do
		--Reference Wheel Orientation
		local Ref=(CFrame.new(v.Position-((v.Arm.CFrame*cfWRot).lookVector),v.Position)*cfYRot).lookVector
		local aRef=1
		local diffMult=1
		local RRdiffMult=1
		local RLdiffMult=1
		local FRdiffMult=1
		local FLdiffMult=1
		if v.Name=="FL" or v.Name=="RL" then aRef=-1 end

		--Differential/Torque-Vectoring
		if _Tune.DifferentialType=='Old' then
			if v.Name=="FL" or v.Name=="FR" then
				diffMult=math.max(0,math.min(1,1+((((v.RotVelocity.Magnitude-fwspeed)/fwspeed)/(math.max(_Tune.FDiffSlipThres,1)/100))*((_Tune.FDiffLockThres-50)/50))))
				if _Tune.Config == "AWD" then
					diffMult=math.max(0,math.min(1,diffMult*(1+((((fwspeed-cwspeed)/cwspeed)/(math.max(_Tune.CDiffSlipThres,1)/100))*((_Tune.CDiffLockThres-50)/50)))))
				end
			elseif v.Name=="RL" or v.Name=="RR" then
				diffMult=math.max(0,math.min(1,1+((((v.RotVelocity.Magnitude-rwspeed)/rwspeed)/(math.max(_Tune.RDiffSlipThres,1)/100))*((_Tune.RDiffLockThres-50)/50))))
				if _Tune.Config == "AWD" then
					diffMult=math.max(0,math.min(1,diffMult*(1+((((rwspeed-cwspeed)/cwspeed)/(math.max(_Tune.CDiffSlipThres,1)/100))*((_Tune.CDiffLockThres-50)/50)))))
				end
			end
		else
			if v.Name=="FR" then
				local avg=((v.RotVelocity.Magnitude/car.Wheels.FL.RotVelocity.Magnitude)-1)*(_Tune.FDiffPreload/10)
				FRdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.FDiffPower/100)*avg*_GThrot) + ((_Tune.FDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
				FLdiffMult=2-FRdiffMult
			elseif v.Name=="FL" then
				local avg=((v.RotVelocity.Magnitude/car.Wheels.FR.RotVelocity.Magnitude)-1)*(_Tune.FDiffPreload/10)
				FLdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.FDiffPower/100)*avg*_GThrot) + ((_Tune.FDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
				FRdiffMult=2-FLdiffMult
			elseif v.Name=="RR" then
				local avg=((v.RotVelocity.Magnitude/car.Wheels.RL.RotVelocity.Magnitude)-1)*(_Tune.RDiffPreload/10)
				RRdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.RDiffPower/100)*avg*_GThrot) + ((_Tune.RDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
				RLdiffMult=2-RRdiffMult
			elseif v.Name=="RL" then
				local avg=((v.RotVelocity.Magnitude/car.Wheels.RR.RotVelocity.Magnitude)-1)*(_Tune.RDiffPreload/10)
				RLdiffMult=math.ceil(math.max(0,math.min(2,1-( ((_Tune.RDiffPower/100)*avg*_GThrot) + ((_Tune.RDiffCoast/100)*avg*(1-_GThrot)))))*100)/100
				RRdiffMult=2-RLdiffMult
			end
		end

		_TCSActive = false
		_ABSActive = false
		--Output

		--Apply Power
		local on=1
		if not script.Parent.IsOn.Value then on=0 end
		local throt = effectiveThrot
		local brake = _GBrake

		local engineBrakeActive = (not _ClPressing) and (_CGear ~= 0) and _IsOn
		local eBrake = engineBrakeActive and (EBrakeForce * ((1 - throt) * (_RPM / _Tune.Redline)) * (1 - brake)) or 0

		local clutch = math.clamp((1 - _Clutch)^2, 0, 1)

		local stallRPM = _Tune.IdleRPM * 0.35
		local rpmRatio = math.clamp((_RPM - stallRPM) / (_Tune.IdleRPM - stallRPM), 0, 1)
		local rpmFactor = rpmRatio^0.7

		rpmFactor = math.max(rpmFactor, 0.25)
		local tq = _OutTorque

		--Apply ABS
		local tqABS = 1
		if _ABS and brake>0 and math.abs(v.RotVelocity.Magnitude*(v.Size.x/2) - v.Velocity.Magnitude)-_Tune.ABSThreshold>0 then
			tqABS = 0
		end
		_ABSActive = (tqABS<1)

		local PBrakeV=0
		if _PBrake==true then PBrakeV=1 else PBrakeV=0 end

		local driven = false
		for _,a in pairs(Drive) do if a==v then driven = true end end
		if driven then
			--Apply AWD Vectoring
			if _Tune.Config == "AWD" then
				local bias = (_Tune.TorqueVector+1)/2
				if string.find(v.Name,"F") then
					tq = tq*(1-bias)
				elseif string.find(v.Name,"R") then
					tq = tq*bias
				end
			end

			--Apply TCS
			tqTCS = 1
			if _TCS and throt>0 then
				tqTCS = 1-(math.min(math.max(0,math.abs(v.RotVelocity.Magnitude*(v.Size.x/2) - v.Velocity.Magnitude)-_Tune.TCSThreshold)/_Tune.TCSGradient,1)*(1-(_Tune.TCSLimit/100)))
			end
			if tqTCS < 1 then
				_TCSAmt = tqTCS
				_TCSActive = true
			end

			--Update Forces
			local dir=1
			if _CGear==-1 then dir = -1 end--luaint edit

			if _Tune.ClutchKick and car.DriveSeat.Velocity.Magnitude<_Tune.KickSpeedThreshold and _RPM>_Tune.Redline-_Tune.KickRPMThreshold and v["#BV"].MotorMaxTorque<1 then 
				tq = (tq*_Tune.KickMult)
			end

			local lurchMult = 1.0
			if _LurchTimer > 0 and car.DriveSeat.Velocity.Magnitude < 5 and brake <= 0 then
				lurchMult = 1.0 + ((_LurchTimer / LURCH_DURATION) * (LURCH_PEAK - 1.0))
			end

			local tqMult = throt

			local tqOUT = (tq * tqMult * lurchMult)*(60/workspace:GetRealPhysicsFPS())*(1+(v.RotVelocity.Magnitude/(120-workspace:GetRealPhysicsFPS()))^(1.15+(.07*(1-(60/workspace:GetRealPhysicsFPS())))))*tqTCS*on*clutch

			if v.Name=='RR' then
				v["#AV"].MotorMaxTorque=tqOUT*RRdiffMult*diffMult
			elseif v.Name=='RL' then
				v["#AV"].MotorMaxTorque=tqOUT*RLdiffMult*diffMult
			elseif v.Name=='FR' then
				v["#AV"].MotorMaxTorque=tqOUT*FRdiffMult*diffMult
			elseif v.Name=='FL' then
				v["#AV"].MotorMaxTorque=tqOUT*FLdiffMult*diffMult
			else
				v["#AV"].MotorMaxTorque=tqOUT*diffMult
			end
			v["#AV"].AngularVelocity=rpmWheelTarget*dir

			if string.find(v.Name,"F") then
				v["#BV"].MotorMaxTorque=(FBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+eBrake+(PBrakeForceF*PBrakeV)
			else
				v["#BV"].MotorMaxTorque=(RBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+eBrake+(PBrakeForceR*PBrakeV)
			end
		else--luaint edit
			v["#AV"].MotorMaxTorque=0
			v["#AV"].AngularVelocity=0
			if string.find(v.Name,"F") then
				v["#BV"].MotorMaxTorque=(FBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+(PBrakeForceF*PBrakeV)
			else
				v["#BV"].MotorMaxTorque=(RBrakeForce*(60/workspace:GetRealPhysicsFPS())*brake*tqABS)+(PBrakeForceR*PBrakeV)
			end
		end
	end
end
