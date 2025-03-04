defmodule Magnolia.MixProject do
  use Mix.Project

  def project do
    [
      app: :magnolia,
      version: "0.1.0",
      elixir: "~> 1.18",
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
      extra_applications: [:logger],
      mod: {Magnolia.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.8"},
      {:mint, "~> 1.7"},
      {:mint_web_socket, "~> 1.0"},
      {:typed_struct, "~> 0.3.0"},

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
