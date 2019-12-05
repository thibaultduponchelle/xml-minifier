package XML::Minify;
use 5.008001;
use strict;
use warnings;

our $VERSION = "0.01";

use XML::LibXML; # To be installed from CPAN : sudo cpanm XML::LibXML 
# CPAN rules !

use Exporter 'import';
our @EXPORT_OK = qw(minify);


my %do_not_remove_blanks = ();
my %opt = ();
my $doc;
my $tree;
my $root;
my $parser;
my $output;

sub traverse($$);

sub minify($%) {
	my $string = shift;
	%opt = @_;

	# Reinit output
	$output = "";

	if($opt{agressive}) {
		(defined $opt{remove_empty_text}) or $opt{remove_empty_text} = 1;             # a bit agressive
		(defined $opt{remove_blanks_start}) or $opt{remove_blanks_start} = 1;         # agressive
		(defined $opt{remove_blanks_end}) or $opt{remove_blanks_end} = 1;             # agressive
		(defined $opt{remove_cr_lf_everywhere}) or $opt{remove_cr_lf_everywhere} = 1; # very agressive 
		# Others are either overriden or with the correct value (undefined is false)
	}
	
	# Configurable with expand_entities
	$parser = XML::LibXML->new(expand_entities => $opt{expand_entities});
	$tree = $parser->parse_string($string);
	$parser->process_xincludes($tree);

	$root = $tree->getDocumentElement;

	# I disable automatic xml declaration as : 
	# - It would be printed too late (after pi and subset) and produce broken output
	# - I want to have full control on it
	$XML::LibXML::skipXMLDeclaration = 1;
	$doc = XML::LibXML::Document->new();

	# Configurable with no_prolog : do not put prolog (a bit gressive for readers) 
	# version=1.0 encoding=UTF-8 : choose values
	my $version = $opt{version} || "1.0";
	my $encoding = $opt{encoding} || "UTF-8";
	$opt{no_prolog} or $output  .= "<?xml version=\"$version\" encoding=\"$encoding\"?>";

	my $rootnode;


	# Parsing first level 
	foreach my $flc ($tree->childNodes()) {

		if(($flc->nodeType eq XML_DTD_NODE) or ($flc->nodeType eq XML_DOCUMENT_TYPE_NODE)) { # second is synonym but deprecated
			# Configurable with keep_dtd 
			my $str = $flc->toString();
			# alternative : my $internaldtd = $tree->internalSubset(); my $str = $internaldtd->toString();
			$str =~ s/\R//g;
			$opt{keep_dtd} and $output .= $str;
		
			# XML_ELEMENT_DECL
			# XML_ATTRIBUTE_DECL
			# XML_ENTITY_DECL 
			# XML_NOTATION_DECL

			# I need to manually (yuck) parse the node as XML::LibXML does not provide (wrap) such function
			foreach my $dc ($flc->childNodes()) {
				if($dc->nodeType == XML_ELEMENT_DECL) {
					if($dc->toString() =~ /<!ELEMENT\s+(\w+)\s*\(.*#PCDATA.*\)>/) {
						$do_not_remove_blanks{$1} = "Not ignorable due to DTD declaration !";
					}
				}
			}

			# Some notes : 
			# If I iterate over attributes of the childs of DTD (so ELEMENT, ATTLIST etc..) I get a segfault
			# Probable bug from XML::LibXML similar to https://rt.cpan.org/Public/Bug/Display.html?id=71076

			# If I try to access the content of XML_ENTITY_REF_DECL with getValue I get correct result, but on XML_ELEMENT_DECL I get empty string
			# Seems like there's no function to play with DTD
			# I guess we need to write the perl binding for xmlElementPtr xmlGetDtdElementDesc (xmlDtdPtr dtd, const xmlChar * name)

			# If I try to iterate over childNodes, I never see XML_NOTATION_DECL (why?!)

			# One word about DTD and XML::LibXML : 
			# DTD validation works like a charm of course... 
			# But reading from one xml and set to another with experimental function seems just broken or works very weirdly
			# Segfault when reading big external subset, weird message "can't import dtd" when trying to add DTD...

		} elsif($flc->nodeType eq XML_PI_NODE) {
			# Configurable with keep_pi
			$opt{keep_pi} and $output .= $flc->toString();
		} elsif($flc->nodeType eq XML_COMMENT_NODE) {
			# Configurable with keep_comments
			$opt{keep_comments} and $output .= $flc->toString();
		} elsif($flc->nodeType eq XML_ELEMENT_NODE) { # Actually document node as if we do getDocumentNode
			# "main" tree, only one (parser is protecting us)
			$rootnode = traverse($root, $doc);
			# XML_ATTRIBUTE_NODE
			# XML_TEXT_NODE
			# XML_ENTITY_REF_NODE
			# XML_COMMENT_NODE
			# XML_CDATA_SECTION_NODE

			# Ignore 
			# XML_XINCLUDE_START
			# XML_XINCLUDE_END
			
			# Will stay hidden in any case
			# XML_NAMESPACE_DECL

			# Not Applicable 
			# XML_DOCUMENT_NODE 
			# XML_DOCUMENT_FRAG_NODE
			# XML_HTML_DOCUMENT_NODE
			
			# What is it ?
			# XML_ENTITY_NODE
			
		} else {
			# Should I print these unattended things ?
			# Should it be configurable ?
		}
			
	}
		
	# XML_ELEMENT_NODE            => 1
	# E.G. : <tag></tag> or <tag/>

	# XML_ATTRIBUTE_NODE          => 2
	# E.G. : <tag attribute="value">

	# XML_TEXT_NODE               => 3
	# E.G. : This is a piece of text

	# XML_CDATA_SECTION_NODE      => 4
	# E.G. : <![CDATA[<sender>John Smith</sender>]]>
	# CDATA section (not for parsers)

	# XML_ENTITY_REF_NODE         => 5
	# Entities like &entity;

	# XML_ENTITY_NODE             => 6
	# XML_PI_NODE                 => 7 
	# Processing Instructions like <?xml-stylesheet href="style.css"> 

	# XML_COMMENT_NODE            => 8
	# Comments like <!-- comment -->

	# XML_DOCUMENT_NODE           => 9
	# The document itself

	# XML_DOCUMENT_TYPE_NODE      => 10
	# E.G. : Deprecated, use XML_DOCUMENT_TYPE_NODE

	# XML_DOCUMENT_FRAG_NODE      => 11
	# E.G. : Never read, for use, should be created as element node

	# XML_NOTATION_NODE           => 12
	# E.G. : <!NOTATION GIF SYSTEM "GIF"> seems not working

	# XML_HTML_DOCUMENT_NODE      => 13
	# E.G. : <catalog></catalog>
	# In HTML context, for us, should be treated as a document node

	# XML_DTD_NODE                => 14
	# E.G. : <!DOCTYPE book PUBLIC "blahblah" "http://www.example.com/docbookx.dtd" [

	# XML_ELEMENT_DECL            => 15
	# E.G. : <!ELEMENT element-name EMPTY>

	# XML_ATTRIBUTE_DECL          => 16
	# E.G. : <!ATTLIST image height CDATA #REQUIRED>

	# XML_ENTITY_DECL             => 17
	# E.G. : <!ENTITY Entity2 "<strong>Entity</strong>">

	# XML_NAMESPACE_DECL          => 18
	# E.G. : <catalog xmlns:xsl="http://www.w3.org/1999/XSL/Transform"> 

	# XML_XINCLUDE_START          => 19
	# <xi:include href="inc.xml"/> if we process includes

	# XML_XINCLUDE_END            => 20
	# <xi:include href="inc.xml"/> if we process includes

	$doc->setDocumentElement($rootnode);

	$output .= $doc->toString();

	return $output;
}

# Traverse the document
sub traverse($$) {
        my $node = shift;
        my $outnode = shift;

	my $name = $node->getName();
	my $newnode = $doc->createElement($name);
	if($outnode) {
		$outnode->addChild($newnode);
	}
	$outnode = $newnode;

        my @as = $node->attributes ;
        foreach my $a (@as) { 
                $outnode->setAttribute($a->nodeName, $a->value); 
        }

        foreach my $child ($node->childNodes) {
		if($child->nodeType eq XML_TEXT_NODE) {
			my $str = $child->data;
		        #print "Text node : $str (". $node->getName() . ") ". @{$child->parentNode->childNodes()} ."\n" ;

			# All these substitutions aim to remove indentation that people tend to put in xml files...
			# ...Or just clean on demand (default behavior keeps these blanks)

			# Configurable with remove_blanks_start : remove extra space/lf/cr at the start of the string
			$opt{remove_blanks_start} and $str =~ s/^\s*//g;
			# Configurable with remove_blanks_end : remove extra space/lf/cr at the end of the string
			$opt{remove_blanks_end} and $str =~ s/\s*$//g;
			# Configurable with remove_cr_lf_everywhere : remove extra lf/cr everywhere
			$opt{remove_cr_lf_everywhere} and $str =~ s/\R*//g;
			# Configurable with remove_spaces_everywhere : remove extra spaces everywhere
			$opt{remove_spaces_everywhere} and $str =~ s/ *//g;
			# Configurable with remove_empty_text : remove text nodes that contains only space/lf/cr
			$opt{remove_empty_text} and $str =~ s/^\s*$//g;

			# Let me explain, we could have text nodes basically everywhere, and we don't know if whitespaces are ignorable or not. 
			# As we want to minify the xml, we can't just keep all blanks, because it is generally indentation or spaces that could be ignored.
			# Here is the strategy : 
			# A. If we have <name>   </name> we should keep it anyway (unless forced with argument)
			# B. If we have </name>   </person> we should remove (in this case parent node contains more than one child node : text node + element node)
			# C. If we have <person>   <name> we should remove it (in this case parent node contains more than one child node : text node + element node)
			# D. If we have </person>   <person> we should remove it (in this case parent node contains more than one child node : text node + element node)
			# B, C, D : remove... unless explicitely declared in DTD as potential #PCDATA container
			if( @{$child->parentNode->childNodes()} > 1 ) { 
				# Should it be configurable ? 
				if(!$do_not_remove_blanks{$child->parentNode->getName()}) {
					# DO NOT REMOVE, PROTECTED BY DTD ELEMENT DECL	
				} else {
					$str =~ s/^\s*$//g;
				}
			} 	 

			$outnode->appendText($str);
		} elsif($child->nodeType eq XML_ENTITY_REF_NODE) {
			# Configuration will be done above when creating document
			my $er = $doc->createEntityReference($child->getName());
			$outnode->addChild($er); 
		} elsif($child->nodeType eq XML_COMMENT_NODE) {
			# Configurable with keep_comments
			$opt{keep_comments} and $outnode->addChild($child);
		} elsif($child->nodeType eq XML_CDATA_SECTION_NODE) {
			# Configurable with keep_cdata
			$opt{keep_cdatas} and $outnode->addChild($child);
		} elsif($child->nodeType eq XML_ELEMENT_NODE) {
			$outnode->addChild(traverse($child, $outnode)); 
		}
	} 
	return $outnode;
}


1;

__END__

=encoding utf-8

=head1 NAME

XML::Minify - It's a configurable XML minifier.

=head1 SYNOPSIS

    use XML::Minify qw(minify);

    my $xmlstr = "<person>   <name>tib   </name>   <level>  42  </level>  </person>";
    minify($xmlstr);

Remove all useless formatting between nodes.

Remove dtd (configurable).

Remove processing instructions (configurable)

Remove comments (configurable).

Remove CDATA (configurable).


This is the default and should be perceived as lossyless minification in term of semantic (but it's not completely if you consider these things as data).

If you want a full lossyless minification, just use keep arguments.


In addition, you could be agressive and remove characters in the text nodes (sort of "cleaning") : 

Remove empty text nodes (configurable).

Remove starting blanks (carriage return, line feed, spaces...) (configurable).

Remove ending blanks (carriage return, line feed, spaces...) (configurable).

Remove carriage returns and line feed into text node everywhere (configurable).

=head2 OPTIONS

You can give various options:

=over 4

=item B<expand_entities>

Expand entities. An entity is like &foo; 

=item B<remove_blanks_start>

Remove blanks (spaces, carriage return, line feed...) in front of text nodes. 

For instance 

    <tag>    foo bar</tag> 

will become 

    <tag>foo bar</tag>

It is agressive and therefore lossy compression.

=item B<remove_blanks_end>

Remove blanks (spaces, carriage return, line feed...) at the end of text nodes. 

For instance 

    <tag>foo bar    </tag> 

will become 

    <tag>foo bar</tag>

It is agressive and therefore lossy compression.

=item B<remove_empty_text>

Remove (pseudo) empty text nodes (spaces, carriage return, line feed...). 

For instance 

    <tag>foo\nbar</tag> 

will become 

    <tag>foobar</tag>

It is agressive and therefore lossy compression.

=item B<remove_cr_lf_everywhere>

Remove carriage returns and line feed everywhere (inside text !). 

Very agressive and therefore lossy compression.

=item B<keep_comments>

Keep comments, by default they are removed. 

A comment is something like :

    <!-- comment -->

=item B<keep_cdata>

Keep cdata, by default they are removed. 

A CDATA is something like : 

    <![CDATA[ my cdata ]]>

=item B<keep_pi>

Keep processing instructions. 

A processing instruction is something like :

    <?xml-stylesheet href="style.css"/>

=item B<keep_dtd>

Keep DTD.

=item B<no_prolog>

Do not put prolog (having no prolog is agressive for XML readers).

Prolog is at the start of the XML file and look like this :

    <?xml version="1.0" encoding="UTF-8"?>";

=item B<version>

Specify version.

=item B<encoding>

Specify encoding.

=item B<agressive>

Short alias for agressive mode. 
Enables options B<remove_blanks_start>, B<remove_blanks_end> B<remove_empty_text> and B<remove_cr_lf_eveywhere> if they are not defined only.

Other options still keep their value.

=back 

=head1 LICENSE

Copyright (C) Thibault DUPONCHELLE.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Thibault DUPONCHELLE E<lt>thibault.duponchelle@gmail.comE<gt>

=cut

