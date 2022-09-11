-- Post Init. This is to stop using traces and other functions, as they can cause a crash if used before.
if not _NIKNAKS_POSTENTITY then
	hook.Add("InitPostEntity","NikNaks_InitPostEntity", function()
		_NIKNAKS_POSTENTITY = true
		if _MODULES["niknaks"] then
			hook.Run("NikNaks._LoadPathOptions")
		end
		hook.Remove("InitPostEntity","NikNaks_InitPostEntity")
	end)
end