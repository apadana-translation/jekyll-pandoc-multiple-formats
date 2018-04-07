# Copyright (c) 2012-2018 Nicolás Reynolds <fauno@endefensadelsl.org>
#               2012-2013 Mauricio Pasquier Juan <mpj@endefensadelsl.org>
#               2013      Brian Candler <b.candler@pobox.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module Jekyll

class PandocGenerator < Generator
  safe true

  attr_accessor :site, :config

  def doc_categories_hash()
    hash = Hash.new { |h, key| h[key] = [] }

    @site.collections.each do |name, collection|
      collection.docs.each do |doc|
        doc.data['categories'].each { |t| hash[t] << doc } if doc.data['categories']
      end
    end

    hash.values.each { |posts| posts.sort!.reverse! }
    hash
  end

  def generate_post_for_output(post, output)
    Jekyll.logger.debug 'Pandoc:', post.data['title']

    pandoc_file = PandocFile.new(@site, output, post)
    return unless pandoc_file.write

    @site.keep_files << pandoc_file.relative_path
    @pandoc_files << pandoc_file
  end

  def generate_collection_doc_for_output(collection, post, output)

    # TODO get regex from collection data, not hard-coded
    build_rel_path = post.relative_path.gsub(/_poems/, 'text')
    build_rel_path = build_rel_path.gsub(/\.md\Z/, ".#{output}")
    build_path = "#{@site.in_dest_dir.dup}/#{build_rel_path}"

    # Does the output file already exist from a previous build?
    if File.file?(build_path)

      # Find out the modification times of the post and the existing output file
      prev_build_mtime = File.mtime(build_path)
      post_mtime = File.mtime(post.path)

      # Don't build again if the post hasn't been modified since the previous build
      if post_mtime < prev_build_mtime
        Jekyll.logger.info "Pandoc:", "'#{post.data['title']}' has not been modified since the previous build. Skipping this file…"
        # Add to keep_files so that old output file isn't cleaned
        @site.keep_files << build_rel_path
        return
      end
    end

    pandoc_file = PandocFile.new(@site, output, post)
    return unless pandoc_file.write
    Jekyll.logger.info "Pandoc:", "Generating '#{post.data['title']}'"
    @site.keep_files << pandoc_file.relative_path
    @pandoc_files << pandoc_file
  end

  def generate_category_for_output(category, docs, output)

    # fetch corresponding category data
    categories_data = @site.data['categories']
    category_title = categories_data.dig(category, 'name')
    cat_rel_path = @site.config.dig('pandoc', 'bundle_permalink').gsub(/:slug\.:output_ext/, "#{Utils.slugify(category_title)}.#{output}")
    cat_path = "#{@site.in_dest_dir.dup}/#{cat_rel_path}"

    # Does the output file already exist from a previous build?
    if File.file?(cat_path)

      # Get the mtime of the previous build
      cat_prev_build_mtime = File.mtime(cat_path)
      rebuild_cat = false

      # Loop thru the docs to see if any of them have been modified since the category was previously built
      docs.each do |doc|
        if File.mtime(doc.path) > cat_prev_build_mtime
          rebuild_cat = true
          break
        end
      end

      # Don't build again if there's not a recently modified doc
      if rebuild_cat != true
        Jekyll.logger.debug "Pandoc:", "Category '#{category_title}' has not been modified since the previous build. Skipping this file…"
        # Add to keep_files so that old output file isn't cleaned
        @site.keep_files << cat_rel_path
        return
      end
    end

    sorted_docs = docs.sort_by { | doc |
      doc.data["order"] || 10000
    }

    pandoc_file = PandocFile.new(@site, output, sorted_docs, category_title)

    if @site.keep_files.include? pandoc_file.relative_path
      Jekyll.logger.warn 'Pandoc:',
        "#{pandoc_file.relative_path} is a category file AND a post file. Change the category name to fix this"
      return
    end

    return unless pandoc_file.write
    Jekyll.logger.info "Pandoc:", "Generating category '#{category_title}'"
    @site.keep_files << pandoc_file.relative_path
    @pandoc_files << pandoc_file
  end

  def generate_full_for_output(output)
    title = @site.config.dig('title')
    Jekyll.logger.info 'Pandoc:', "Generating full file '#{title}'"
    # We order collection by category, then by order.
    full = @site.posts.docs.reject { |p| p.data.dig('full') }.sort_by do |p|
      [ p.data['date'], p.data['categories'].first.to_s ]
    end

    full_file = PandocFile.new(@site, output, full, title, { full: true })
    full_file.write
    @site.keep_files << full_file.relative_path
    @pandoc_files << full_file
  end

  def generate_full_collection_for_output(collection, output)
    title = @site.config.dig('title')

    coll_rel_path = @site.config.dig('pandoc', 'bundle_permalink').gsub(/:slug\.:output_ext/, "#{Utils.slugify(title)}.#{output}")
    coll_path = "#{@site.in_dest_dir.dup}/#{coll_rel_path}"

    # Does the output file already exist from a previous build?
    if File.file?(coll_path)

      # Get the mtime of the previous build
      coll_prev_build_mtime = File.mtime(coll_path)
      rebuild_coll = false

      # Loop thru the docs to see if any of them have been modified since the collection was previously built
      collection.docs.each do |doc|
        if File.mtime(doc.path) > coll_prev_build_mtime
          rebuild_coll = true
          break
        end
      end

      # Don't build again if there's not a recently modified doc in the collection
      if rebuild_coll != true
        Jekyll.logger.info "Pandoc:", "Collection '#{title}' has not been modified since the previous build. Skipping this file…"
        # Add to keep_files so that old output file isn't cleaned
        @site.keep_files << coll_rel_path
        return
      end
    end

    # sort by category (chapter), then frontmatter 'order' value
    full = collection.docs.sort_by do |doc|
      [ doc.data['categories'], doc.data['order'] ]
    end

    full_file = PandocFile.new(@site, output, full, title, { full_collection: true })
    full_file.write
    Jekyll.logger.info "Pandoc:", "Generating full collection '#{title}'"
    @site.keep_files << full_file.relative_path
    @pandoc_files << full_file
  end

  def generate(site)
    @site     ||= site
    @config   ||= JekyllPandocMultipleFormats::Config.new(@site.config['pandoc'])

    return if @config.skip?

    # we create a single array of files
    @pandoc_files = []

    @config.outputs.each_pair do |output, _|
      Jekyll.logger.info 'Pandoc:', "Generating #{output} files"
      @site.posts.docs.each do |post|
        Jekyll::Hooks.trigger :posts, :pre_render, post, { format: output }
        generate_post_for_output(post, output) if @config.generate_posts?
        Jekyll::Hooks.trigger :posts, :post_render, post, { format: output }
      end

      @site.collections.each do |name, collection|
        collection.docs.each do |doc|
          Jekyll::Hooks.trigger :documents, :pre_render, doc, { format: output }
          generate_collection_doc_for_output(collection, doc, output) if @config.generate_posts?
          Jekyll::Hooks.trigger :documents, :post_render, doc, { format: output }
        end
      end

      if @config.generate_categories?
        def categories
          if Jekyll::VERSION >= '3.0.0'
            doc_categories_hash()
          else
            @site.post_attr_hash('categories')
          end
        end
        categories.each_pair do |title, docs|
          generate_category_for_output(title, docs, output)
        end
      end

      general_full_for_output(output) if @config.generate_full_file?

      @site.collections.reject { |c| c['posts'] }.each do |name, collection|
        generate_full_collection_for_output(collection, output) if @config.generate_full_collection_file?
      end
    end

    @pandoc_files.each do |pandoc_file|
      # If output is PDF, we also create the imposed PDF
      next unless pandoc_file.pdf?

      if @config.imposition?

        imposed_file = JekyllPandocMultipleFormats::Imposition
          .new(pandoc_file.path, pandoc_file.papersize,
          pandoc_file.sheetsize, pandoc_file.signature)

        imposed_file.write
        @site.keep_files << imposed_file.relative_path(@site.dest)
      end

      # If output is PDF, we also create the imposed PDF
      if @config.binder?

        binder_file = JekyllPandocMultipleFormats::Binder
          .new(pandoc_file.path, pandoc_file.papersize,
          pandoc_file.sheetsize)

        binder_file.write
        @site.keep_files << binder_file.relative_path(@site.dest)
      end

      # Add covers to PDFs after building ready for print files
      if pandoc_file.has_cover?
        # Generate the cover
        next unless pandoc_file.pdf_cover!
        united_output = pandoc_file.path.gsub(/\.pdf\Z/, '-cover.pdf')
        united_file = JekyllPandocMultipleFormats::Unite
          .new(united_output, [pandoc_file.pdf_cover,pandoc_file.path])

        if united_file.write
          # Replace the original file with the one with cover
          FileUtils.rm_f(pandoc_file.path)
          FileUtils.mv(united_output, pandoc_file.path)
        end
      end
    end
  end
end
end
