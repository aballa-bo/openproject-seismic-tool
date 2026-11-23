# frozen_string_literal: true

# Work package types and custom fields that carry the damage found during a
# survey: "AeDES – Danno strutturale" and "AeDES – Danno non strutturale".
# The survey form (Modello A-DC) is compiled from these work packages.
#
# Idempotent (matches by name) and never aborts the migration: whatever cannot
# be created (API differences between OpenProject versions) is reported and can
# be created by hand under Administration with the same names.
class CreateAedesWorkPackageTypes < ActiveRecord::Migration[7.0]
  TYPES = ["AeDES – Danno strutturale", "AeDES – Danno non strutturale"].freeze

  def up
    return say("WorkPackageCustomField/Type not available -- skipped") unless defined?(::WorkPackageCustomField) && defined?(::Type)

    types = TYPES.map { |name| find_or_create_type(name) }.compact
    fields = SeismicTool::AedesWorkPackages::FIELD_SPECS.filter_map { |spec| find_or_create_field(spec) }

    fields.each do |cf, spec|
      types.each do |type|
        next unless spec[:types].include?(type.name == TYPES.first ? :structural : :non_structural)

        link(cf, type)
      end
    end
  rescue StandardError => e
    say "AeDES work package types skipped: #{e.class}: #{e.message}"
  end

  def down
    names = SeismicTool::AedesWorkPackages::FIELD_SPECS.map { |s| s[:name] }
    ::WorkPackageCustomField.where(name: names).destroy_all if defined?(::WorkPackageCustomField)
    ::Type.where(name: TYPES).each { |t| t.destroy if t.work_packages.none? } if defined?(::Type)
  end

  private

  def find_or_create_type(name)
    type = ::Type.find_by(name: name)
    return type if type

    type = ::Type.new(name: name)
    type.position = (::Type.maximum(:position) || 0) + 1 if type.respond_to?(:position=)
    type.is_in_roadmap = true if type.respond_to?(:is_in_roadmap=)
    type.is_milestone = false if type.respond_to?(:is_milestone=)
    type.color = ::Color.first if type.respond_to?(:color=) && defined?(::Color)
    type.save!
    copy_workflows(type)
    type
  rescue StandardError => e
    say "could not create type #{name.inspect}: #{e.class}: #{e.message}"
    nil
  end

  # A type without workflows cannot change status: borrow them from the standard type.
  def copy_workflows(type)
    source = ::Type.respond_to?(:standard_type) ? ::Type.standard_type : ::Type.where.not(id: type.id).order(:position).first
    type.workflows.copy_from_type(source) if source && type.respond_to?(:workflows)
  rescue StandardError => e
    say "no workflows copied for #{type.name}: #{e.message}"
  end

  def find_or_create_field(spec)
    cf = ::WorkPackageCustomField.find_by(name: spec[:name])
    return [cf, spec] if cf

    cf = ::WorkPackageCustomField.new(name: spec[:name], field_format: spec[:format])
    cf.is_for_all = true
    cf.is_required = false
    cf.is_filter = true
    cf.searchable = false
    cf.multi_value = true if spec[:multi] && cf.respond_to?(:multi_value=)
    cf.position = (::WorkPackageCustomField.maximum(:position) || 0) + 1
    (spec[:options] || []).each_with_index { |v, i| cf.custom_options.build(value: v, position: i + 1) }
    cf.save!
    [cf, spec]
  rescue StandardError => e
    say "could not create custom field #{spec[:name].inspect}: #{e.class}: #{e.message}"
    nil
  end

  # OpenProject <= 16: Type#custom_fields; >= 17: custom fields hang off type variants.
  def link(cf, type)
    if type.respond_to?(:custom_fields)
      type.custom_fields << cf unless type.custom_fields.include?(cf)
    elsif cf.respond_to?(:type_variants) && defined?(::TypeVariant)
      ::TypeVariant.where(type_id: type.id).find_each { |v| cf.type_variants << v unless cf.type_variants.include?(v) }
    end
  rescue StandardError => e
    say "could not enable #{cf.name} on #{type.name}: #{e.message}"
  end
end
