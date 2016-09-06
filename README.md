# GuMDrop

A static site generator for developers. Don't run this on untrusted data - it
will `eval` any Ruby scripts it finds in the data folder! _That's really bad_.

It also `eval`s `[site folder]/site.rb`, `[site folder]/helpers.rb`, and, like,
every ruby file in your system given a creative enough bad actor (or one
who knows how to symlink). Even if I got rid of that, it uses YAML as its
configuration format, which Ruby's own documentation states should not be used
on untrusted data. Point is, this is a website development framework, not a
blogging platform.

Essentially, a GuMDrop site is made up of 3 basic parts:
- A folder full of data
- A set of handlebars templates
- A script piping the former into the latter and specifying where to output the
  result

Let's go over the structure of each.

## Data

This is a folder in the root of your GuMDrop site folder named `data`. This
folder will become the root of the site data tree. Any data folder can contain
any number of the following (in descriptions of what they get converted to,
`[filename]` refers to the base name without extensions - so `path/to/file.ext`
would have the `[filename]` "file"):
- `.yaml`, `.yml` files:
  - These get converted to a node in the tree with the key `:[filename]` and
    the value of a hash representing the file's data. For example:
    ```yaml
    one:
      two: three
    four:
    - five: six
      seven: eight
    - nine: ten
    ```
    would be converted to the hash
    ```ruby
    {
      one: { two: 'three' },
      four: [ { five: 'six', seven: 'eight' }, { nine: 'ten' } ],
    }
    ```
    All keys get symbolized, so you don't need to write `:key: value` (you can,
    but it will be treated equally to `key: value`).
- `.md`, `.markdown` files:
  - These get converted to a node with the key `:[filename]` and the value of a
    hash containing a single k/v pair:
    `{ contents: "HTML representation of the markdown" }`
- `.rb` files:
  - These get evaluated and converted to a node in the tree with the key
    `:[filename]` and the value of whatever the file evaluates to. Each Ruby
    file should be evaluated exactly once, if it doesn't then that is a bug.
    Ruby files should evaluate to a hash, for reasons explained below. This
    option is for getting information from an API or a database, or generating
    it dynamically. This could be emulated by putting this information in the
    `site.rb` file, but it seems conceptually simpler to simply have ruby files
    that evaluate to hashes.
- folders:
  - These get evaluated and converted to a node in the tree with the key
    `:[filename]` and the value of recursively converting this folder to a hash,
    using the same rules as converting the data folder.

*Important*: If multiple files or folders are found with the same name, their
values will be merged. Because of this, `.rb` files must evaluate to a `Hash`.
The order in which files are visited is unspecified, so if the values have the
same key it is unspecified which of the possible values are included in the
output.

There is one exception to this rule: if a file or folder with the name "index"
is found, that node is merged into the parent. So, for example, a folder
containing only an `index.yml` file will be a node in the data tree with the
folder name as the key and the contents of `index.yml` as the value. You could
have a huge nested set of folders called `index` if you wanted to, but that's
probably pointless. Hell though, some people do worse things for fun, so go
crazy.

## Templates

These get recursively converted to an object with methods that take a hash and
return a string that is the result of evaluating the template with the same name
as the method using the given hash. For example, a templates folder with the
following structure:
```
templates
├── index.hbs
├── item.hbs
└── partials
    └── layout.hbs
```
will be converted to Ruby objects roughly corresponding to the following code:
```ruby
class PartialsClass
  def layout(data)
    # evaluate templates/partials/layout.hbs with data
  end
end

class TemplatesClass
  def partials
    @partials ||= PartialClass.new
  end

  def index(data)
    # evaluate templates/index.hbs with data
  end

  def item(data)
    # evaluate templates/item.hbs with data
  end
end
```
This is actually just implemented with `define_singleton_method` though, so
these classes are just for the purposes of explanation.

Additionally, the templates will all be registered as partials using their
path relative to the `templates` folder as identifiers, so for example,
`templates/partials/layout.hbs` could be included in another template with
```handlebars
{{> partials/layout }}
```
Templates in the root of the `templates` folder can be included with just their
name, such as
```handlebars
{{> item }}
```

## Site script

This should be a Ruby file called `site.rb` in the root of your site that
evaluates to a `Proc` (or other object responding to `call`) taking two
arguments: the hash of data and the templates object (both explained earlier).
The data will have all keys symbolised, so if you need to access an element of
the data index using a symbol. This proc should return a hash representing the
file structure that one wants to see in the output - so
```ruby
Proc.new do |data, templates|
	{
		"." => templates.index(data),
		"items" => {
		  "first" => templates.item(data[:items][:first]),
		  "second" => templates.item(data[:items][:second]),
		}
	]
end
```
is converted to
```
out
├── index.html
├── first
│   └── index.html
└── second
    └── index.html
```
The keys are just path fragments, so you can use `"."` to refer to the current
path, or even `".."` to go up a level. The paths are converted to folders
containing an `index.html` file containing the value if it is a `String`, or the
result of recursively converting the value to a folder tree if it is a `Hash`.

## Additional

Additionally, you can register helpers for the handlebars templates by defining
a file called `helpers.rb` in the root of your site that evaluates to a hash
with keys that are symbols of the name of the helper and the value that is the
helper proc. Since `handlebars.rb` is used, you can
[check their documentation](https://github.com/cowboyd/handlebars.rb) for
information about the definition of helpers.

Finally, if you define a folder called `static` in the root of your site, any
files inside this folder will be copied to the `out` directory, retaining folder
structure. Essentially, GuMDrop just runs `cp -r static/* out/` after generating
the site. Because of this, any files in `static` will stomp over dynamic ones,
so put them in subfolders.
