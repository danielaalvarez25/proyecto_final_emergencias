defmodule Albergue do
  @moduledoc """
  Albergue con capacidad máxima y registro de las personas alojadas.

  - codigo: identificador único, en mayúsculas (por ejemplo "A01")
  - nombre: nombre del albergue
  - zona: zona donde está ubicado
  - capacidad: cantidad máxima de personas
  - ocupacion: cantidad de personas alojadas, nunca mayor que la capacidad
  - personas: lista con los documentos de las personas alojadas
  - recursos: códigos de los recursos asociados
  - necesidades: ids de las necesidades asociadas
  """

  defstruct codigo: "",
            nombre: "",
            zona: "",
            capacidad: 0,
            ocupacion: 0,
            personas: [],
            recursos: [],
            necesidades: []

  @doc """
  Crea un albergue sin personas alojadas.

  ## Ejemplo

  iex> Albergue.crear("A01", "Albergue Norte", "zona_norte", 150)
  """
  def crear(codigo, nombre, zona, capacidad, ocupacion \\ 0) do
    %Albergue{
      codigo: codigo,
      nombre: nombre,
      zona: zona,
      capacidad: capacidad,
      ocupacion: ocupacion
    }
  end

  defimpl String.Chars, for: Albergue do
    def to_string(%Albergue{
          codigo: codigo,
          nombre: nombre,
          zona: zona,
          capacidad: capacidad,
          ocupacion: ocupacion
        }) do
      "#{codigo}: #{nombre} (#{zona}), ocupación #{ocupacion}/#{capacidad}"
    end
  end
end
