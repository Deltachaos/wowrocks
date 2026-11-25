local xml = {}

xml.HEADER = (
   '<Ui xmlns="http://www.blizzard.com/wow/ui/" '
   .. 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
   .. 'xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\\FrameXML\\UI.xsd">'
)

local function include_line(rel)
   return '  <Include file="' .. rel:gsub("/", "\\") .. '"/>'
end

function xml.generate(module_files, footer)
   local lines = { xml.HEADER }
   for _, rel in ipairs(module_files) do
      lines[#lines + 1] = include_line(rel)
   end
   if footer and footer ~= "" then
      lines[#lines + 1] = include_line(footer)
   end
   lines[#lines + 1] = "</Ui>"
   return table.concat(lines, "\n") .. "\n"
end

return xml
