
################################################################################
# WeBWorK Online Homework Delivery System
# Copyright � 2000-2007 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/lib/WeBWorK/ContentGenerator/Instructor/ShowAnswers.pm,v 1.20 2006/10/10 10:58:54 dpvc Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

package WeBWorK::ContentGenerator::Instructor::ShowAnswers;
use base qw(WeBWorK::ContentGenerator::Instructor);

=head1 NAME

WeBWorK::ContentGenerator::Instructor::ShowAnswers.pm  -- display past answers of students

=cut

use strict;
use warnings;
#use CGI;
use WeBWorK::CGI;
use WeBWorK::Utils qw(sortByName ); 
use HTML::Entities;

sub initialize {
	my $self       = shift;
	my $r          = $self->r;
	my $urlpath    = $r->urlpath;
	my $db         = $r->db;
	my $ce         = $r->ce;
	my $authz      = $r->authz;
	my $courseName = $urlpath->arg("courseID");
	my $user       = $r->param('user');
	
	unless ($authz->hasPermissions($user, "view_answers")) {
		$self->addbadmessage("You aren't authorized to view past answers");
		return;
	}
	
	# The stop acting button doesn't perform a submit action and so
	# these extra parameters are passed so that if an instructor stops
	# acting the current studentID, setID and problemID will be maintained

	my $extraStopActingParams;
	$extraStopActingParams->{studentUser} = $r->param('studentUser');
	$extraStopActingParams->{setID} = $r->param('setID');
	$extraStopActingParams->{problemID} = $r->param('problemID');
	$r->{extraStopActingParams} = $extraStopActingParams;

}


sub body {
	my $self          = shift;
	my $r             = $self->r;
	my $urlpath       = $r->urlpath;
	my $db            = $r->db;
	my $ce            = $r->ce;
	my $authz         = $r->authz;
	my $root          = $ce->{webworkURLs}->{root};
	my $courseName    = $urlpath->arg('courseID');  
	my $setName       = $r->param('setID');     # these are passed in the search args in this case
	my $problemNumber = $r->param('problemID');
	my $user          = $r->param('user');
	my $key           = $r->param('key');
	my $studentUser   = $r->param('studentUser') if ( defined($r->param('studentUser')) );
	
	my $instructor = $authz->hasPermissions($user, "access_instructor_tools");

	return CGI::em("You are not authorized to view past answers") unless $authz->hasPermissions($user, "view_answers");

	
	my $showAnswersPage   = $urlpath->newFromModule($urlpath->module,  $r, courseID => $courseName);
	my $showAnswersURL    = $self->systemLink($showAnswersPage,authen => 0 );
	my @answerTypes;
	my $renderAnswers = 0;
	# Figure out if MathJax is available
	if (('MathJax' ~~ @{$ce->{pg}->{displayModes}})) {
	    print CGI::start_script({type=>"text/javascript", src=>"$ce->{webworkURLs}->{MathJax}"}), CGI::end_script();
	    $renderAnswers = 1;
	}


	#####################################################################
	# print form
	#####################################################################

	#only instructors should be able to veiw other people's answers.
	
	if ($instructor) {
	    print CGI::p(),CGI::hr();
	    
	    print CGI::start_form("POST", $showAnswersURL,-target=>'information'),
	    $self->hidden_authen_fields;
	    print CGI::submit(-name => 'action', -value=>'Past Answers for')," &nbsp; ",
	    CGI::textfield(-name => 'studentUser', -value => $studentUser, -size =>10 ),
	    " &nbsp; Set: &nbsp;",
	    CGI::textfield( -name => 'setID', -value => $setName, -size =>10  ), 
	    " &nbsp; Problem: &nbsp;",
	    CGI::textfield(-name => 'problemID', -value => $problemNumber,-size =>10  ),  
	    " &nbsp; ";
	    print CGI::end_form();
	}

		#####################################################################
		# print result table of answers
		#####################################################################

	# If not instructor then force table to use current user-id
	if (!$instructor) {
	    $studentUser = $user;
	}

	return CGI::span({class=>'ResultsWithError'}, 'You must provide
			    a student ID, a set ID, and a problem number.')
	    unless defined($studentUser)  && defined($setName) 
	    && defined($problemNumber);
	    
	my @pastAnswerIDs = $db->listProblemPastAnswers($courseName, $studentUser, $setName, $problemNumber);

	print CGI::start_table({id=>"past-answer-table", border=>0,cellpadding=>0,cellspacing=>3,align=>"center"});
	print CGI::h3("Past Answers for $studentUser, set $setName, problem $problemNumber" );
	print "No entries for $studentUser set $setName, problem $problemNumber" unless @pastAnswerIDs;

	# changed this to use the db for the past answers.  

	#set up a silly problem to figure out what type the answers are
	#(why isn't this stored somewhere)
	my $displayMode   = $self->{displayMode};
	my $formFields = { WeBWorK::Form->new_from_paramable($r)->Vars }; 
	my $set = $db->getMergedSet($studentUser, $setName); # checked
	my $problem = $db->getMergedProblem($studentUser, $setName, $problemNumber); # checked
	my $userobj = $db->getUser($studentUser);
	my $pg = WeBWorK::PG->new(
	    $ce,
	    $userobj,
	    $key,
	    $set,
	    $problem,
	    $set->psvn, # FIXME: this field should be removed
	    $formFields,
	    { # translation options
		displayMode     => 'plainText',
		showHints       => 0,
		showSolutions   => 0,
		refreshMath2img => 0,
		processAnswers  => 1,
		permissionLevel => $db->getPermissionLevel($studentUser)->permission,
		effectivePermissionLevel => $db->getPermissionLevel($studentUser)->permission,
	    },
	    );
	
	# check to see what type the answers are.  right now it only checks for essay but could do more
	my %answerHash = %{ $pg->{answers} };
	
	foreach (sortByName(undef, keys %answerHash)) {
	    push(@answerTypes,defined($answerHash{$_}->{type})?$answerHash{$_}->{type}:'undefined');
	}
		
	foreach my $answerID (@pastAnswerIDs) {
	    my $pastAnswer = $db->getPastAnswer($answerID);
	    my $answers = $pastAnswer->answer_string;
	    my $scores = $pastAnswer->scores;
	    my $time = $self->formatDateTime($pastAnswer->timestamp);

	    my @scores = split(//, $scores);
	    my @answers = split(/\t/,$answers);
	    
	    my @row = (CGI::td({width=>10}),CGI::td({style=>"color:#808080"},CGI::small($time)));
	    my $td = {nowrap => 1};
	    my $num_ans = $#answers;
	    for (my $i = 0; $i <= $num_ans; $i++) {
		my $answer = $answers[$i];
		my $score = shift(@scores); 
		#Only color answer if its an instructor
		if ($instructor) {
		    $td->{style} = $score? "color:#006600": "color:#660000";
		} 
		delete($td->{style}) unless $answer ne "" && defined($score) && $answerTypes[$i] ne 'essay';

		my $answerstring;
		if ($answer eq '') {		    
		    $answerstring  = CGI::small(CGI::i("empty")) if ($answer eq "");
		} elsif (!$renderAnswers) {
		    $answerstring = HTML::Entities::encode_entities($answer);
		} elsif ($answerTypes[$i] eq 'Value (Formula)') {
		    $answerstring = '`'.HTML::Entities::encode_entities($answer).'`';
		} else {
		    $answerstring = HTML::Entities::encode_entities($answer);
		}

		push(@row,CGI::td({width=>20}),CGI::td($td,$answerstring));
	    }

	    if ($pastAnswer->comment_string) {
		push(@row,CGI::td({width=>20}),CGI::td("Comment: ".HTML::Entities::encode_entities($pastAnswer->comment_string)));
	    }

	    print CGI::Tr(@row);

	    
	}

	print CGI::end_table();
	    
	if ($renderAnswers) {
	    print <<EOS;
	    <script type="text/javascript">
		MathJax.Hub.Queue([ "Typeset", MathJax.Hub, "past-answer-table"]);
	    </script>
EOS
	}
	
	return "";
}

sub byData {
  my ($A,$B) = ($a,$b);
  $A =~ s/\|[01]*\t([^\t]+)\t.*/|$1/; # remove answers and correct/incorrect status
  $B =~ s/\|[01]*\t([^\t]+)\t.*/|$1/;
  return $A cmp $B;
}

1;
