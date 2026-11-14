defmodule Zona do
  @moduledoc """
  Zona afectada por la emergencia.

  La información se organiza en una jerarquía: una zona tiene sectores
  (Sector) y cada sector tiene puntos de atención (PuntoAtencion).

  """
  defstruct codigo: "",
            nombre: "",
            nivel: :medio,
            personas_estimadas: 0,
            sectores: []

  @doc """
  Crea una zona sin sectores.
  """
  def crear(codigo, nombre, nivel, personas_estimadas \\ 0) do
    %Zona{
      codigo: codigo,
      nombre: nombre,
      nivel: nivel,
      personas_estimadas: personas_estimadas
    }
  end

  defimpl String.Chars, for: Zona do
    def to_string(%Zona{codigo: codigo, nombre: nombre, nivel: nivel, sectores: sectores}) do
      "#{codigo}: #{nombre}, nivel #{nivel}, #{length(sectores)} sectores"
    end
  end
end
