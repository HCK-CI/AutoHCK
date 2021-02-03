# frozen_string_literal: true

require 'fileutils'
require 'nokogiri'
require './lib/exceptions'

def read_xml(xml_file, logger)
  Nokogiri::XML(File.read(xml_file))
rescue Errno::ENOENT, Nokogiri::SyntaxError
  logger.fatal("Could not open #{xml_file} file")
  raise OpenXmlError, "Could not open #{xml_file} file"
end

def update_xml(xml_doc, replacement_list, logger)
  logger.debug("update_xml: Document namespaces #{xml_doc.namespaces}")

  replacement_list.each do |replacement|
    logger.debug("update_xml: Processing #{replacement}")

    if xml_doc.namespaces.size > 0
      nodes = xml_doc.xpath("//#{xml_doc.namespaces.keys.first}:*[text()='#{replacement.first[0]}']", xml_doc.namespaces)
    else
      nodes = xml_doc.xpath("//*[text()='#{replacement.first[0]}']")
    end

    nodes.each do |node|
      logger.debug("update_xml: Updating #{node}")
      node.content = replacement.first[1]
    end
  end
end

def write_xml(xml_doc, xml_file, logger)
  File.write(xml_file, xml_doc.to_xml.to_str)
rescue Errno::ENOENT, Nokogiri::SyntaxError
  logger.fatal("Could not open #{xml_file} file")
  raise OpenXmlError, "Could not open #{xml_file} file"
end