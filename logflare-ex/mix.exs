defmodule LogflareEx.MixProject do
  use Mix.Project

  @prerelease System.get_env("PRERELEASE_VERSION")
  @version_suffix if(@prerelease, do: "-#{@prerelease}", else: "")
  def project do
    [
      app: :logflare_ex,
      version: "0.1.0#{@version_suffix}",
      build_path: "./_build",
      config_path: "./config/config.exs",
      deps_path: "./deps",
      lockfile: "./mix.lock",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        "test.format": :test,
        "test.compile": :test
      ],
      package: package()
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

  defp aliases do
    [
      "test.compile": ["compile --warnings-as-errors"],
      "test.format": ["format --check-formatted"],
      "test.build": ["hex.build"]
    ]
  end

  defp package() do
    [
      description: "Logflare Elixir SDK",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Logflare/logflare-sdk"}
    ]
  end
end
