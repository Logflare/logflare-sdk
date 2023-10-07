defmodule LogflareEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :logflare_ex,
      version: "0.0.0",
      build_path: "./_build",
      config_path: "./config/config.exs",
      deps_path: "./deps",
      lockfile: "./mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.0"},
      {:finch, "~> 0.10"},
      {:bertex, "~> 1.3"},
      {:jason, ">= 1.0.0"},
      {:bypass, "~> 2.1", only: :test},
      {:benchee, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:mimic, "~> 1.7", only: :test},
      {:typed_struct, "~> 0.3.0"}
    ]
  end
end
