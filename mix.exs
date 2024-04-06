defmodule Magnolia.MixProject do
  use Mix.Project

  def project do
    [
      app: :magnolia,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Magnolia",
      package: package(),
      description: "A Discord library for Elixir.",
      source_url: "https://github.com/leastrio/magnolia"
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
       {:gun, "~> 2.0"},
       {:req, "~> 0.4.0"},
       {:jason, "~> 1.4"},
       {:typed_struct, "~> 0.3.0"},
       {:certifi, "~> 2.8"},
       {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
    ]
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/leastrio/magnolia"}
    ]
  end
end
