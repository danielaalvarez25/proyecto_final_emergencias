defmodule Usuario do
  @moduledoc """
  Usuario que participa en la coordinación de la emergencia.

  """

  defstruct username: "",
            password: "",
            nombre: "",
            tipo: :ciudadano,
            zona: "",
            conectado: false,
            actividad: []

  @doc """
  Crea un usuario sin sesión abierta y sin actividad.
  """
  def crear(username, password, tipo, zona, nombre \\ "") do
    %Usuario{
      username: username,
      password: password,
      nombre: nombre,
      tipo: tipo,
      zona: zona
    }
  end

  defimpl String.Chars, for: Usuario do
    def to_string(%Usuario{username: username, tipo: tipo, zona: zona}) do
      "#{username} (#{tipo}, zona #{zona})"
    end
  end
end
