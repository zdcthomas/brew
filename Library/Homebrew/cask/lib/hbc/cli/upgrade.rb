module Hbc
  class CLI
    class Upgrade < AbstractCommand
      option "--greedy", :greedy, false
      option "--quiet",  :quiet, false
      option "--force", :force, false
      option "--skip-cask-deps", :skip_cask_deps, false

      def initialize(*)
        super
        self.verbose = ($stdout.tty? || verbose?) && !quiet?
      end

      def run
        outdated_casks = casks(alternative: lambda {
          Caskroom.casks.select do |cask|
            cask.outdated?(greedy?)
          end
        }).select do |cask|
          raise CaskNotInstalledError, cask unless cask.installed? || force?
          cask.outdated?(true)
        end

        if outdated_casks.empty?
          oh1 "No Casks to upgrade"
          return
        end

        ohai "Casks with `auto_updates` or `version :latest` will not be upgraded" if args.empty?
        oh1 "Upgrading #{Formatter.pluralize(outdated_casks.length, "outdated package")}, with result:"
        puts outdated_casks.map { |f| "#{f.full_name} #{f.version}" } * ", "

        outdated_casks.each do |old_cask|
          odebug "Started upgrade process for Cask #{old_cask}"
          raise CaskUnavailableError.new(old_cask, "The Caskfile is missing!") if old_cask.installed_caskfile.nil?

          old_cask = CaskLoader.load(old_cask.installed_caskfile)

          old_cask_installer =
            Installer.new(old_cask, binaries:  binaries?,
                                    verbose:   verbose?,
                                    force:     force?,
                                    upgrade:   true)

          new_cask = CaskLoader.load(old_cask.to_s)

          new_cask_installer =
            Installer.new(new_cask, binaries:       binaries?,
                                    verbose:        verbose?,
                                    force:          force?,
                                    skip_cask_deps: skip_cask_deps?,
                                    require_sha:    require_sha?,
                                    upgrade:        true,
                                    quarantine:     quarantine?)

          started_upgrade = false
          new_artifacts_installed = false

          begin
            # Start new Cask's installation steps
            new_cask_installer.check_conflicts

            new_cask_installer.print_caveats

            new_cask_installer.fetch

            # Move the old Cask's artifacts back to staging
            old_cask_installer.start_upgrade
            # And flag it so in case of error
            started_upgrade = true

            # Install the new Cask
            new_cask_installer.stage

            new_cask_installer.install_artifacts
            new_artifacts_installed = true

            new_cask_installer.enable_accessibility_access

            # If successful, wipe the old Cask from staging
            old_cask_installer.finalize_upgrade
          rescue CaskError => e
            new_cask_installer.uninstall_artifacts if new_artifacts_installed
            new_cask_installer.purge_versioned_files
            old_cask_installer.revert_upgrade if started_upgrade
            raise e
          end
        end
      end

      def self.help
        "upgrades all outdated casks"
      end
    end
  end
end
