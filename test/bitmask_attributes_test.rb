require 'test_helper'

class BitmaskAttributesTest < ActiveSupport::TestCase

  def self.context_with_classes(label,campaign_class,company_class)
    context label do
      setup do
        @campaign_class = campaign_class
        @company_class = company_class
      end

      teardown do
        @company_class.destroy_all
        @campaign_class.destroy_all
      end

      should "return all defined values of a given bitmask attribute" do
        assert_equal @campaign_class.values_for_medium, [:web, :print, :email, :phone]
      end

      should "can assign single value to bitmask" do
        assert_stored @campaign_class.new(:medium => :web), :web
      end

      should "can assign multiple values to bitmask" do
        assert_stored @campaign_class.new(:medium => [:web, :print]), :web, :print
      end

      should "can add single value to bitmask" do
        campaign = @campaign_class.new(:medium => [:web, :print])
        assert_stored campaign, :web, :print
        campaign.medium << :phone
        assert_stored campaign, :web, :print, :phone
      end

      should "ignores duplicate values added to bitmask" do
        campaign = @campaign_class.new(:medium => [:web, :print])
        assert_stored campaign, :web, :print
        campaign.medium << :phone
        assert_stored campaign, :web, :print, :phone
        campaign.medium << :phone
        assert_stored campaign, :web, :print, :phone
        campaign.medium << "phone"
        assert_stored campaign, :web, :print, :phone
        assert_equal 1, campaign.medium.select { |value| value == :phone }.size
        assert_equal 0, campaign.medium.select { |value| value == "phone" }.size
      end

      should "can assign new values at once to bitmask" do
        campaign = @campaign_class.new(:medium => [:web, :print])
        assert_stored campaign, :web, :print
        campaign.medium = [:phone, :email]
        assert_stored campaign, :phone, :email
      end

      should "can save bitmask to db and retrieve values transparently" do
        campaign = @campaign_class.new(:medium => [:web, :print])
        assert_stored campaign, :web, :print
        assert campaign.save
        assert_stored @campaign_class.find(campaign.id), :web, :print
      end

      should "can add custom behavor to value proxies during bitmask definition" do
        campaign = @campaign_class.new(:medium => [:web, :print])
        assert_raises NoMethodError do
          campaign.medium.worked?
        end
        assert_nothing_raised do
          campaign.misc.worked?
        end
        assert campaign.misc.worked?
      end

      should "cannot use unsupported values" do
        assert_unsupported { @campaign_class.new(:medium => [:web, :print, :this_will_fail]) }
        campaign = @campaign_class.new(:medium => :web)
        assert_unsupported { campaign.medium << :this_will_fail_also }
        assert_unsupported { campaign.medium = [:so_will_this] }
      end

      should "can determine bitmasks using convenience method" do
        assert @campaign_class.bitmask_for_medium(:web, :print)
        assert_equal(
          @campaign_class.bitmasks[:medium][:web] | @campaign_class.bitmasks[:medium][:print],
          @campaign_class.bitmask_for_medium(:web, :print)
        )
      end

      should "assert use of unknown value in convenience method will result in exception" do
        assert_unsupported { @campaign_class.bitmask_for_medium(:web, :and_this_isnt_valid)  }
      end

      should "hash of values is with indifferent access" do
        string_bit = nil
        assert_nothing_raised do
          assert (string_bit = @campaign_class.bitmask_for_medium('web', 'print'))
        end
        assert_equal @campaign_class.bitmask_for_medium(:web, :print), string_bit
      end

      should "save bitmask with non-standard attribute names" do
        campaign = @campaign_class.new(:Legacy => [:upper, :case])
        assert campaign.save
        assert_equal [:upper, :case], @campaign_class.find(campaign.id).Legacy
      end

      should "ignore blanks fed as values" do
        campaign = @campaign_class.new(:medium => [:web, :print, ''])
        assert_stored campaign, :web, :print
      end

      context "checking" do
        setup { @campaign = @campaign_class.new(:medium => [:web, :print]) }

        context "for a single value" do
          should "be supported by an attribute_for_value convenience method" do
            assert @campaign.medium_for_web?
            assert @campaign.medium_for_print?
            assert !@campaign.medium_for_email?
          end

          should "be supported by the simple predicate method" do
            assert @campaign.medium?(:web)
            assert @campaign.medium?(:print)
            assert !@campaign.medium?(:email)
          end
        end

        context "for multiple values" do
          should "be supported by the simple predicate method" do
            assert @campaign.medium?(:web, :print)
            assert !@campaign.medium?(:web, :email)
          end
        end
      end

      context "named scopes" do
        setup do
          @company = @company_class.create(:name => "Test Co, Intl.")
          @campaign1 = @company.campaigns.create :medium => [:web, :print]
          @campaign2 = @company.campaigns.create
          @campaign3 = @company.campaigns.create :medium => [:web, :email]
        end

        should "support retrieval by any value" do
          assert_equal [@campaign1, @campaign3], @company.campaigns.with_medium
        end

        should "support retrieval by one matching value" do
          assert_equal [@campaign1], @company.campaigns.with_medium(:print)
        end

        should "support retrieval by any matching value (OR)" do
          assert_equal [@campaign1, @campaign3], @company.campaigns.with_any_medium(:print, :email)
        end

        should "support retrieval by all matching values" do
          assert_equal [@campaign1], @company.campaigns.with_medium(:web, :print)
          assert_equal [@campaign3], @company.campaigns.with_medium(:web, :email)
        end

        should "support retrieval for no values" do
          assert_equal [@campaign2], @company.campaigns.without_medium
          assert_equal [@campaign2], @company.campaigns.no_medium
        end

        should "support retrieval without a specific value" do
          assert_equal [@campaign2, @campaign3], @company.campaigns.without_medium(:print)
        end
      end

      should "can check if at least one value is set" do
        campaign = @campaign_class.new(:medium => [:web, :print])
        assert campaign.medium?

        campaign = @campaign_class.new
        assert !campaign.medium?
      end

      should "find by bitmask values" do
        campaign = @campaign_class.new(:medium => [:web, :print])
        assert campaign.save

        assert_equal(
          @campaign_class.find(:all, :conditions => ['medium & ? <> 0', @campaign_class.bitmask_for_medium(:print)]),
          @campaign_class.medium_for_print
        )

        assert_equal @campaign_class.medium_for_print.first, @campaign_class.medium_for_print.medium_for_web.first

        assert_equal [], @campaign_class.medium_for_email
        assert_equal [], @campaign_class.medium_for_web.medium_for_email
      end

      should "find no values" do
        campaign = @campaign_class.create(:medium => [:web, :print])
        assert campaign.save

        assert_equal [], @campaign_class.no_medium

        campaign.medium = []
        assert campaign.save

        assert_equal [campaign], @campaign_class.no_medium
      end


      private

        def assert_unsupported(&block)
          assert_raises(ArgumentError, &block)
        end

        def assert_stored(record, *values)
          values.each do |value|
            assert record.medium.any? { |v| v.to_s == value.to_s }, "Values #{record.medium.inspect} does not include #{value.inspect}"
          end
          full_mask = values.inject(0) do |mask, value|
            mask | @campaign_class.bitmasks[:medium][value]
          end
          assert_equal full_mask, record.medium.to_i
        end

    end
  end

  context_with_classes 'Campaign with null attributes',CampaignWithNull,CompanyWithNull
  context_with_classes 'Campaign without null attributes',CampaignWithoutNull,CompanyWithoutNull
end