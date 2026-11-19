-- Keeps the menubar independent from the windows loader. The actual window module sets this when
-- ui/windows is registered.

local tipsWindowWrapper = {}

tipsWindowWrapper.tipsWindow = nil

function tipsWindowWrapper.show()
    if tipsWindowWrapper.tipsWindow then
        tipsWindowWrapper.tipsWindow.show()
    end
end

return tipsWindowWrapper
