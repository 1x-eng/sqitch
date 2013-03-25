package App::Sqitch::Command::checkout;

use 5.010;
use strict;
use warnings;
use utf8;
use Mouse;
use Mouse::Util::TypeConstraints;
use Locale::TextDomain qw(App-Sqitch);
use App::Sqitch::X qw(hurl);
use App::Sqitch::Plan;
use Encode qw(decode);
use Path::Class qw(dir);
use Hash::Merge 'merge';
use Git::Wrapper;
use namespace::autoclean;

extends 'App::Sqitch::Command';
with 'App::Sqitch::CommandOptions::deploy_variables';
with 'App::Sqitch::CommandOptions::revert_variables';

our $VERSION = '0.954';

has verify => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
    default  => 0,
);

has log_only => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
    default  => 0,
);

has no_prompt => (
    is  => 'ro',
    isa => 'Bool'
);

has mode => (
    is  => 'ro',
    isa => enum([qw(
        change
        tag
        all
    )]),
    default => 'all',
);

has git => (
    is       => 'ro',
    isa      => 'Git::Wrapper',
    required => 1,
    lazy     => 1,
    default  => sub { Git::Wrapper->new(dir) }
);

sub options {
    return qw(
        mode=s
        verify!
        set|s=s%
        set-deploy|d=s%
        set-revert|r=s%
        log-only
        y
    );
}

sub configure {
    my ( $class, $config, $opt, $params ) = @_;
    return merge $params || {}, {
        mode      => $opt->{mode}
                  || $config->get( key => 'checkout.mode' )
                  || $config->get( key => 'deploy.mode' )
                  || 'all',
        verify    => $opt->{verify}
                  // $config->get( key => 'checkout.verify', as => 'boolean' )
                  // $config->get( key => 'deploy.verify',   as => 'boolean' )
                  // 0,
        log_only  => $opt->{log_only} || 0,
        no_prompt =>  delete $opt->{y}
                  // $config->get( key => 'checkout.no_prompt', as  => 'bool' )
                  // $config->get( key => 'revert.no_prompt',   as  => 'bool' )
                  // 0,
    };
}

sub execute {
    my ( $self, $branch) = @_;
    $self->usage unless defined $branch;
    my $sqitch = $self->sqitch;
    my $git    = $self->git;
    my $engine = $sqitch->engine;
    $engine->with_verify( $self->verify );
    $engine->no_prompt( $self->no_prompt );

    # What branch are we on?
    my ($current_branch) = $git->rev_parse(qw(--abbrev-ref HEAD));
    hurl {
        ident   => 'checkout',
        message => __x('Already on branch {branch}', branch => $branch),
        exitval => 1,
    } if $current_branch eq $branch;

    # Instantitate a plan without calling $sqitch->plan.
    my $from_plan = App::Sqitch::Plan->new( sqitch => $sqitch );

    # Load the target plan from Git, assuming the same path.
    my $to_plan = App::Sqitch::Plan->new( sqitch => $sqitch )->parse(
        # XXX Handle missing file/no contents.
        decode 'UTF-8', join(
            "\n" => $git->show("$branch:" . $sqitch->plan_file )
        ), Encode::FB_CROAK
    );

    # Find the last change the plans have in common.
    my $last_common_change;
    for my $change ($to_plan->changes){
        last unless $from_plan->get( $change->id );
        $last_common_change = $change;
    }

    hurl checkout => __x(
        'Target branch {target} has no canges in common with source branch {source}',
        target => $branch,
        source => $current_branch,
    ) unless $last_common_change;

    $sqitch->info(__x(
        'Last change before the branches diverged: {last_change}',
        last_change => $last_common_change->format_name_with_tags,
    ));

    # Revert to the last common change.
    if (my %v = %{ $self->revert_variables }) { $engine->set_variables(%v) }
    $engine->plan( $from_plan );
    $engine->revert( $last_common_change->id, $self->log_only );

    # Check out the new branch.
    $git->checkout($branch);

    # Deploy!
    if (my %v = %{ $self->deploy_variables}) { $engine->set_variables(%v) }
    $engine->plan( $to_plan );
    $engine->deploy( undef, $self->mode, $self->log_only);
    return $self;
}

1;

__END__

=head1 Name

App::Sqitch::Command::checkout - Revert, change checkout a VCS branch, and redeploy

=head1 Synopsis

  my $cmd = App::Sqitch::Command::checkout->new(%params);
  $cmd->execute;

=head1 Description

If you want to know how to use the C<checkout> command, you probably want to
be reading C<sqitch-checkout>. But if you really want to know how the
C<checkout> command works, read on.

=head1 Interface

=head2 Class Methods

=head3 C<options>

  my @opts = App::Sqitch::Command::checkout->options;

Returns a list of L<Getopt::Long> option specifications for the command-line
options for the C<checkout> command.

=head2 Instance Methods

=head3 C<execute>

  $checkout->execute;

Executes the checkout command.

=head1 See Also

=over

=item L<sqitch-checkout>

Documentation for the C<checkout> command to the Sqitch command-line client.

=item L<sqitch>

The Sqitch command-line client.

=back

=head1 Authors

=over

=item * Ronan Dunklau <ronan@dunklau.fr>

=item * David E. Wheeler <david@justatheory.com>

=back

=head1 License

Copyright (c) 2013 Ronan Dunklau & iovation Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut
