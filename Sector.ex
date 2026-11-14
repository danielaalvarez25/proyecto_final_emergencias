defmodule Sector do
  @moduledoc """
  Sector de una zona, contiene puntos de atención.

  """

  defstruct nombre: "",
            personas_estimadas: 0,
            puntos: []

  def crear(nombre, personas_estimadas \\ 0) do
    %Sector{
      nombre: nombre,
      personas_estimadas: personas_estimadas
    }
  end

  defimpl String.Chars, for: Sector do
    def to_string(%Sector{nombre: nombre, puntos: puntos}) do
      "#{nombre}, #{length(puntos)} puntos de atención"
    end
  end
end
