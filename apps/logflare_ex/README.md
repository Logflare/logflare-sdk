# LogflareEx

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `logflare_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:logflare_ex, "~> 0.1.0"}
  ]
end
```

And add in to `application.ex`:
```elixir
  def start(_type, _args) do
    children = [
      {Finch, name: LogflareEx.Finch}
    ]

    opts = [strategy: :one_for_one, name: LogflareApiClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Benchmarks

### Jason vs Bertex
```

Operating System: macOS
CPU Information: Apple M1 Pro
Number of Available Cores: 10
Available memory: 32 GB
Elixir 1.12.3
Erlang 24.1.7

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: none specified
Estimated total run time: 28 s


Name                          ips        average  deviation         median         99th %
bertex encode large        614.32        1.63 ms     ±2.40%        1.63 ms        1.73 ms
bertex decode large        417.23        2.40 ms    ±22.53%        2.16 ms        3.14 ms
jason encode large          57.26       17.46 ms     ±2.68%       17.37 ms       20.43 ms
jason decode large          47.24       21.17 ms     ±2.29%       21.20 ms       23.22 ms

Comparison: 
bertex encode large        614.32
bertex decode large        417.23 - 1.47x slower +0.77 ms
jason encode large          57.26 - 10.73x slower +15.84 ms
jason decode large          47.24 - 13.01x slower +19.54 ms
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/logflare_ex](https://hexdocs.pm/logflare_ex).

