# Ruby Native Modules Cheatsheet

This cheatsheet covers commonly used native Ruby modules from the standard library and how to use them.

## What “native modules” means

Ruby ships with a **standard library**: modules and classes that come with Ruby itself or are commonly bundled with it. You usually load them with `require` and then use their constants and methods.

Examples:

```ruby
require 'json'
require 'time'
require 'net/http'
```

## Common standard library modules

### Core language helpers

#### `Math`
Mathematical functions and constants.

```ruby
Math.sqrt(16)      # 4.0
Math::PI           # 3.141592653589793
Math.sin(0)        # 0.0
```

#### `Enumerable`
Mix-in for collection traversal. It becomes available when a class defines `each`.

```ruby
[1, 2, 3].map { |n| n * 2 }
[1, 2, 3].select { |n| n > 1 }
[1, 2, 3].reduce(:+)
```

#### `Comparable`
Mix-in for defining ordering via `<=>`.

```ruby
class Person
  include Comparable
  attr_reader :age
  def initialize(age) = @age = age
  def <=>(other) = age <=> other.age
end
```

### Data and text

#### `JSON`
Read and write JSON.

```ruby
require 'json'
obj = JSON.parse('{"a":1}')
text = JSON.generate({ a: 1 })
```

#### `CSV`
Parse and generate CSV files.

```ruby
require 'csv'
rows = CSV.read('data.csv', headers: true)
CSV.open('out.csv', 'w') do |csv|
  csv << %w[name age]
  csv << ['Alice', 30]
end
```

#### `YAML`
Serialize structured data in YAML.

```ruby
require 'yaml'
obj = YAML.load_file('config.yml')
text = { a: 1 }.to_yaml
```

#### `Time`
Work with times and dates.

```ruby
require 'time'
now = Time.now
parsed = Time.parse('2026-05-02 10:00:00')
```

#### `Date` and `DateTime`
Date handling.

```ruby
require 'date'
d = Date.today
dt = DateTime.now
```

### Files and paths

#### `File`
Read, write, and inspect files.

```ruby
File.read('input.txt')
File.write('out.txt', 'hello')
File.exist?('data.csv')
```

#### `Dir`
Directory operations.

```ruby
Dir.entries('.')
Dir.mkdir('tmp')
Dir.glob('*.rb')
```

#### `Pathname`
Object-oriented path handling.

```ruby
require 'pathname'
p = Pathname.new('src/app.rb')
p.basename
p.dirname
```

#### `Tempfile`
Temporary files.

```ruby
require 'tempfile'
Tempfile.create('demo') do |f|
  f.write('hello')
  f.rewind
  puts f.read
end
```

### Networking and web

#### `Socket`
Low-level network sockets.

```ruby
require 'socket'
```

#### `Net::HTTP`
HTTP client.

```ruby
require 'net/http'
require 'uri'
uri = URI('https://example.com')
res = Net::HTTP.get_response(uri)
puts res.code
```

#### `OpenURI`
Quick URL reading.

```ruby
require 'open-uri'
puts URI.open('https://example.com').read
```

#### `URI`
Parse and build URIs.

```ruby
require 'uri'
u = URI.parse('https://example.com/path?x=1')
```

### Concurrency and processes

#### `Thread`
Native Ruby threads.

```ruby
t = Thread.new { sleep 1; puts 'done' }
t.join
```

#### `Mutex`
Protect shared state.

```ruby
mutex = Mutex.new
mutex.synchronize do
  # critical section
end
```

#### `Queue`
Thread-safe queue.

```ruby
q = Queue.new
q << 1
q.pop
```

#### `Process`
Process utilities.

```ruby
Process.pid
Process.wait(pid)
```

#### `Open3`
Run external commands and capture output.

```ruby
require 'open3'
out, err, status = Open3.capture3('ruby', '-v')
```

### Compression and archives

#### `Zlib`
Compression utilities.

```ruby
require 'zlib'
compressed = Zlib::Deflate.deflate('hello')
plain = Zlib::Inflate.inflate(compressed)
```

#### `Digest`
Hashes and checksums.

```ruby
require 'digest'
Digest::SHA256.hexdigest('hello')
```

#### `Archive::Tar` and `Gem::Package` utilities
Often used through gems or packaging tools, but not always part of minimal Ruby installs.

## Time-saving patterns

### Requiring a library

```ruby
require 'json'
require 'csv'
require 'time'
```

### Checking if a feature is available

```ruby
begin
  require 'psych'
rescue LoadError
  puts 'psych not available'
end
```

### Namespaces

Ruby modules act as namespaces.

```ruby
module Tools
  class Parser
  end
end
```

Use them with `::`:

```ruby
Tools::Parser.new
```

## Common module vs class distinction

A **module** is often used for namespacing or mix-ins.
A **class** is used to create objects.

Examples:
- `Math` is a module.
- `JSON` is a module.
- `File` is a class.
- `Time` is a class.

## Practical starter set

If you’re learning Ruby, these are the most useful standard libraries to know first:

- `json`
- `csv`
- `time`
- `date`
- `fileutils`
- `pathname`
- `net/http`
- `uri`
- `open3`
- `digest`
- `zlib`
- `thread`

## Example script

```ruby
require 'json'
require 'time'
require 'net/http'
require 'uri'

uri = URI('https://example.com')
res = Net::HTTP.get_response(uri)

info = {
  fetched_at: Time.now.iso8601,
  status: res.code,
  body_length: res.body.length
}

puts JSON.pretty_generate(info)
```

## Notes

- Some libraries are part of the standard library but may need to be installed separately depending on Ruby version or packaging.
- Load libraries with `require` before using them.
- Use `module` for namespacing and mix-ins, `class` for objects.
