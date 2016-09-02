HashObj.new({ a: "Hello!" })
	
Proc.new do |data, templates|
	{
		"." => templates.index(data),
	}.merge Hash[
		data.items.map do |name, item|
			[name, templates.item(item)]
		end
	]
end
