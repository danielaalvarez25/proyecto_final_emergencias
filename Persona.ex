defmodule Persona do
  @moduledoc """
  Persona afectada por la emergencia, localizable por documento, nombre,
  zona o estado.
  """

  defstruct id: "",
            documento: "",
            nombre: "",
            edad: nil,
            zona: "",
            estado: :sin_informacion,
            historial: []

  @doc """
  Crea una persona sin historial de cambios de estado.
  """
  def crear(id, documento, nombre, edad, zona, estado \\ :sin_informacion) do
    %Persona{
      id: id,
      documento: documento,
      nombre: nombre,
      edad: edad,
      zona: zona,
      estado: estado
    }
  end

  defimpl String.Chars, for: Persona do
    def to_string(%Persona{documento: documento, nombre: nombre, zona: zona, estado: estado}) do
      "#{nombre} (#{documento}), zona #{zona}, estado #{estado}"
    end
  end
end
